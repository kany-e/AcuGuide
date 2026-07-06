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

    // Camera position. Front (default) = coach yourself in the mirrored selfie preview.
    // Back = point the phone at ANOTHER person's hand (two-person use: one holds and presses,
    // the camera watches the receiver) — un-mirrored, like any rear-camera view.
    @Published private(set) var usingFront = true

    // Bumped on the main thread AFTER a flip's session reconfigure commits. The preview layer's
    // connection is RECREATED by the reconfigure — after SwiftUI already re-rendered for the
    // usingFront change — so without this second render pass the fresh connection never gets its
    // portrait rotation re-applied and the view comes up upside down (user-reported).
    @Published private(set) var configGeneration = 0

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
        // NOTE: session configuration is DEFERRED to start() — creating an AVCaptureDeviceInput is
        // what makes iOS present the camera-permission alert, and this object is built when the
        // coach view appears, BEFORE CameraGate has shown its in-context explainer. Configuring
        // here fired the system dialog cold over the safety gate.
    }

    // Queue-confined. Configure lazily, and only once authorized — CameraGate guarantees start()
    // is only reached in the authorized state, so the permission prompt always follows the explainer.
    private var configured = false
    private func configureIfNeeded() {
        guard !configured, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        installInput(position: usingFront ? .front : .back)

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

    // Queue-confined. Validate the replacement BEFORE touching the session's inputs, so a missing/
    // unavailable camera never commits an input-less session. Shared by configure + flip.
    @discardableResult
    private func installInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
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

    func start() {
        queue.async {
            self.configureIfNeeded()   // deferred from init: runs only once authorized (via CameraGate)
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
    func stop()  {
        ShadowLocalizer.shared.logSummary()   // dump the session's per-point/regime shadow telemetry
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    // Flip front ⇄ back (two-person mode). Reconfigures the session on the capture queue; the
    // mirroring convention updates atomically with it (front = mirrored selfie, back = un-mirrored),
    // and the engine drops EVERYTHING keyed to the old coordinate space/scene (smoothers, sticky
    // role anchors, face verdict, stale ring/tip) — a flip is a new scene, not a wobble.
    func flipCamera() {
        usingFront.toggle()
        let pos: AVCaptureDevice.Position = usingFront ? .front : .back
        let m = mirrored
        engine.cameraFlipped()
        queue.async { [weak self] in
            guard let self else { return }
            self.queueMirrored = m
            guard self.configured else { return }   // never authorized/configured → nothing to swap yet
            self.session.beginConfiguration()
            // installInput validates the replacement BEFORE removing the old input; on failure
            // (Simulator, camera in use) the session keeps its previous input and we revert the
            // published state so the UI doesn't report a camera that never installed.
            if !self.installInput(position: pos) {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.usingFront.toggle(); self.engine.cameraFlipped() }
                let mBack = !m
                self.queue.async { self.queueMirrored = mBack }
                return
            }
            if let conn = self.session.outputs.compactMap({ $0.connection(with: .video) }).first {
                self.videoConnection = conn
                conn.forcePortrait()
                conn.setMirrored(false)   // data output stays un-mirrored; the PREVIEW mirrors
            }
            self.session.commitConfiguration()
            // Second render pass so CameraPreview re-applies portrait+mirroring to the connection
            // that was just recreated (see configGeneration).
            DispatchQueue.main.async { self.configGeneration += 1 }
        }
    }

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
        // Shared converter (HandVision) → identical points to the M3 label harness (zero skew).
        // flipX = queueMirrored (capture-queue-confined; matches the mirrored preview).
        guard let s = HandVision.sample(obs, flipX: queueMirrored) else { return nil }
        // mirroredCoords: isDorsal's sign convention needs the coordinate parity — chirality never
        // flips with our manual mirror, so back-camera (un-mirrored) frames negate the cross product.
        return Hand(points: s.points, chirality: obs.chirality, confidence: s.confidence,
                    mirroredCoords: queueMirrored)
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
    var configGeneration = 0   // changes force updateUIView AFTER a flip's reconfigure (fresh connection)

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
