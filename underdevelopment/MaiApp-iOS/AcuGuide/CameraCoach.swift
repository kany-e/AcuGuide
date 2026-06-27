import AVFoundation
import Vision
import SwiftUI

// Owns the capture session + Vision hand-pose pipeline and drives a CoachEngine.
// Native equivalent of the web app's useMediaPipe + useHandClassifier.
final class CameraCoach: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let engine: CoachEngine
    var acupoint: Acupoint

    // The selfie (front) camera is used; the preview is mirrored so it feels natural.
    private let usingFront = true

    // SINGLE SOURCE OF TRUTH for mirroring. `mirrored` drives BOTH the preview connection
    // and the landmark x-flip, so they can never disagree. `mirrorFlip` is a runtime debug
    // toggle (a switch in the coach view) to invert it on-device for field calibration.
    @Published var mirrorFlip = false
    var mirrored: Bool { usingFront != mirrorFlip }   // XOR

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
        configure()
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
            // Deliver portrait-upright buffers so landmark coords share the portrait
            // overlay's normalized space (the app is portrait-locked).
            applyPortrait(to: conn)
            // Data output stays UN-mirrored; the PREVIEW does the mirroring and buildHand
            // flips landmark x. This keeps `mirrored` the one knob that controls both.
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = false
            }
        }
        session.commitConfiguration()
    }

    private func applyPortrait(to conn: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let portrait: CGFloat = 90
            if conn.isVideoRotationAngleSupported(portrait) { conn.videoRotationAngle = portrait }
        } else {
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        }
    }

    // Derive the Vision orientation from the capture connection (NOT a hardcoded `.up`),
    // handling the iOS 16 (`videoOrientation`) vs iOS 17+ (`videoRotationAngle`) API split.
    // The connection is configured portrait + un-mirrored, so the upright orientation is
    // `.up`; we still confirm it from the connection so a platform that ignored the portrait
    // request is rotated correctly rather than silently wrong.
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
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: visionOrientation(), options: [:])
        try? handler.perform([request])
        let hands = (request.results ?? []).compactMap { buildHand($0) }
        let now = CACurrentMediaTime()
        DispatchQueue.main.async { self.engine.update(hands: hands, point: self.acupoint, now: now) }
    }

    private func buildHand(_ obs: VNHumanHandPoseObservation) -> Hand? {
        let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                   .indexMCP, .middleMCP, .ringMCP, .pinkyMCP]
        let flipX = mirrored   // single source of truth (matches the mirrored preview)
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

// Live camera preview layer. `mirrored` is updated live (debug toggle) via updateUIView.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        applyMirror(v)
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { applyMirror(uiView) }

    private func applyMirror(_ v: PreviewView) {
        guard let conn = v.videoLayer.connection else { return }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirrored
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
