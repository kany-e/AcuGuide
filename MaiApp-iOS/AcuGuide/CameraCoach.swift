import AVFoundation
import Vision
import SwiftUI

// Owns the capture session + Vision hand-pose pipeline and drives a CoachEngine.
// Native equivalent of the web app's useMediaPipe + useHandClassifier.
final class CameraCoach: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let engine: CoachEngine
    var acupoint: Acupoint

    private let queue = DispatchQueue(label: "camera.coach")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let usingFront = true   // selfie camera; we mirror to feel natural

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
        session.commitConfiguration()
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
        try? handler.perform([request])
        let hands = (request.results ?? []).compactMap { buildHand($0) }
        let now = CACurrentMediaTime()
        DispatchQueue.main.async { self.engine.update(hands: hands, point: self.acupoint, now: now) }
    }

    private func buildHand(_ obs: VNHumanHandPoseObservation) -> Hand? {
        let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                   .indexMCP, .middleMCP, .ringMCP, .pinkyMCP]
        var pts: [HandJoint: CGPoint] = [:]
        for j in joints {
            guard let rp = try? obs.recognizedPoint(j.vision), rp.confidence > 0.3 else { continue }
            // Vision: normalized, BOTTOM-left origin. Flip y -> top-left. Mirror x for front cam.
            var x = rp.location.x
            let y = 1 - rp.location.y
            if usingFront { x = 1 - x }
            pts[j] = CGPoint(x: x, y: y)
        }
        guard pts[.wrist] != nil else { return nil }
        return Hand(points: pts, chirality: obs.chirality)
    }
}

// Live camera preview layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        v.videoLayer.connection?.automaticallyAdjustsVideoMirroring = false
        v.videoLayer.connection?.isVideoMirrored = mirrored
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
