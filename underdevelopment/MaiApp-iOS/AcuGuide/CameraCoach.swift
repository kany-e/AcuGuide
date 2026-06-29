import AVFoundation
import Vision
import SwiftUI

// Owns the capture session + Vision hand-pose pipeline and drives a CoachEngine.
// Native equivalent of the web app's useMediaPipe + useHandClassifier.
final class CameraCoach: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let engine: CoachEngine
    var acupoint: Acupoint

    // Portrait display aspect (width/height, <1) of the camera frame, published so the overlay can
    // map normalized landmarks through the SAME aspect-fill crop the preview uses (otherwise the
    // ring/press dot are offset+scaled from the visible video). Defaults to 9:16.
    @Published var frameAspect: CGFloat = 9.0 / 16.0
    private var lastAspect: CGFloat = 0

    // The selfie (front) camera is used; the preview is mirrored so it feels natural.
    private let usingFront = true

    // SINGLE SOURCE OF TRUTH for mirroring. `mirrored` (main thread) drives the preview
    // connection; `queueMirrored` is the capture-queue-confined copy that drives the landmark
    // x-flip — so the flag is never read across threads (no data race). Flipping the debug
    // toggle updates the queue copy and resets the One-Euro smoother (negating every landmark
    // x is a full-frame coordinate jump that would otherwise spike the filter's velocity).
    @Published var mirrorFlip = false {
        didSet {
            let m = mirrored
            queue.async { [weak self] in self?.queueMirrored = m }
            engine.smootherReset()
        }
    }
    var mirrored: Bool { usingFront != mirrorFlip }   // XOR — main thread / preview
    private var queueMirrored = true                  // capture queue only

    private let queue = DispatchQueue(label: "camera.coach")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private var videoConnection: AVCaptureConnection?

    init(engine: CoachEngine, acupoint: Acupoint) {
        self.engine = engine
        self.acupoint = acupoint
        super.init()
        queueMirrored = mirrored
        // Configure off the main thread: device discovery + session (re)configuration is slow
        // and must not block the SwiftUI transition into the coach. The serial queue guarantees
        // configure() completes before start() (also queued) runs.
        queue.async { [weak self] in self?.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        let pos: AVCaptureDevice.Position = usingFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video) {
            videoConnection = conn
            // Deliver portrait-upright buffers so landmark coords share the portrait overlay's
            // normalized space (the app is portrait-locked). Data output stays UN-mirrored; the
            // PREVIEW does the mirroring and buildHand flips landmark x to match.
            conn.forcePortrait()
            conn.setMirrored(false)
        }
        session.commitConfiguration()
    }

    // Derive the Vision orientation from the capture connection (NOT a hardcoded `.up`),
    // handling the iOS 16 (`videoOrientation`) vs iOS 17+ (`videoRotationAngle`) API split.
    // The connection is configured portrait + un-mirrored, so the upright orientation is `.up`;
    // we still confirm it from the connection so a platform that ignored the portrait request is
    // rotated correctly rather than silently wrong.
    private func visionOrientation() -> CGImagePropertyOrientation {
        guard let conn = videoConnection else { return .up }
        if #available(iOS 17.0, *) {
            switch Int(conn.videoRotationAngle.rounded()) {
            case 90:  return .up      // portrait (configured)
            case 0:   return .right   // sensor-native landscape, not rotated
            case 180: return .left
            case 270: return .down
            default:  return .up
            }
        } else {
            switch conn.videoOrientation {
            case .portrait:           return .up      // configured
            case .landscapeRight:     return .right   // not rotated to portrait
            case .landscapeLeft:      return .left
            case .portraitUpsideDown: return .down
            @unknown default:         return .up
            }
        }
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        let aspect = CGFloat(min(w, h)) / CGFloat(max(w, h))   // portrait display aspect (W/H)
        if abs(aspect - lastAspect) > 0.001 {
            lastAspect = aspect
            DispatchQueue.main.async { self.frameAspect = aspect }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: visionOrientation(), options: [:])
        try? handler.perform([request])
        let hands = (request.results ?? []).compactMap { buildHand($0) }
        let now = CACurrentMediaTime()
        DispatchQueue.main.async { self.engine.update(hands: hands, point: self.acupoint, now: now) }
    }

    private func buildHand(_ obs: VNHumanHandPoseObservation) -> Hand? {
        // Usable-hand gate == engine.js MIN_CONFIDENCE (0.5): reject low-confidence detections
        // so the live path matches the validated fixture path (which gates presence at 0.5).
        guard obs.confidence >= Float(CoachConst.minConfidence) else { return nil }

        let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                   .indexMCP, .middleMCP, .ringMCP, .pinkyMCP]
        let flipX = queueMirrored   // capture-queue-confined; matches the mirrored preview
        var pts: [HandJoint: CGPoint] = [:]
        for j in joints {
            guard let rp = try? obs.recognizedPoint(j.vision), rp.confidence > 0.3 else { continue }
            // Vision: normalized, BOTTOM-left origin. Flip y -> top-left. Mirror x to match
            // the mirrored preview (data output itself is un-mirrored).
            var x = rp.location.x
            let y = 1 - rp.location.y
            if flipX { x = 1 - x }
            pts[j] = CGPoint(x: x, y: y)
        }
        guard pts[.wrist] != nil else { return nil }
        return Hand(points: pts, chirality: obs.chirality)
    }
}

// Shared connection policy so the data output and the preview can't drift out of sync.
extension AVCaptureConnection {
    func setMirrored(_ on: Bool) {
        guard isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        isVideoMirrored = on
    }
    func forcePortrait() {
        if #available(iOS 17.0, *) {
            if isVideoRotationAngleSupported(90) { videoRotationAngle = 90 }
        } else {
            if isVideoOrientationSupported { videoOrientation = .portrait }
        }
    }
}

// Live camera preview layer. `mirrored` is updated live (debug toggle) via updateUIView, and the
// preview connection is forced to the same portrait orientation as the data output so the video
// and the normalized landmark overlay share one coordinate space.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        apply(v)
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { apply(uiView) }

    private func apply(_ v: PreviewView) {
        guard let conn = v.videoLayer.connection else { return }
        conn.forcePortrait()
        conn.setMirrored(mirrored)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
