import SwiftUI
import AVFoundation
import Vision

// Front-camera capture + Vision plumbing shared by the region locators. Subclasses override
// `detect(...)` to run their own Vision request (face landmarks / body pose) and return marks;
// everything else (session config, portrait, orientation, aspect, mirroring policy) is common.
// Data output stays un-mirrored; the preview mirrors and `detect` flips x — same as the hand coach.
class LocatorCameraBase: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var marks: [LocatorMark] = []
    @Published var frameAspect: CGFloat = 9.0 / 16.0
    let mirrored = true                       // front camera → mirrored selfie preview

    private var lastAspect: CGFloat = 0
    private let queue = DispatchQueue(label: "locator.camera")
    private var videoConnection: AVCaptureConnection?

    override init() { super.init(); queue.async { [weak self] in self?.configure() } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            videoConnection = conn
            conn.forcePortrait()
            conn.setMirrored(false)
        }
        session.commitConfiguration()
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    private func visionOrientation() -> CGImagePropertyOrientation {
        guard let conn = videoConnection else { return .up }
        if #available(iOS 17.0, *) {
            switch Int(conn.videoRotationAngle.rounded()) {
            case 90: return .up; case 0: return .right; case 180: return .left; case 270: return .down
            default: return .up
            }
        } else {
            switch conn.videoOrientation {
            case .portrait: return .up; case .landscapeRight: return .right
            case .landscapeLeft: return .left; case .portraitUpsideDown: return .down
            @unknown default: return .up
            }
        }
    }

    // Subclass hook — run the region's Vision request and return marks (normalized top-left, mirrored).
    func detect(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation, aspect: CGFloat) -> [LocatorMark] { [] }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        let aspect = CGFloat(min(w, h)) / CGFloat(max(w, h))
        if abs(aspect - lastAspect) > 0.001 { lastAspect = aspect; DispatchQueue.main.async { self.frameAspect = aspect } }
        let m = detect(pixel, orientation: visionOrientation(), aspect: aspect)
        DispatchQueue.main.async { self.marks = m }
    }
}

// Shared pieces for the camera acupoint LOCATORS (face, torso, …): a normalized marker and the
// overlay that draws them on an aspect-fill camera preview. Each region ships its own detector
// (face landmarks / body pose) + cun mapping, but the on-screen presentation is identical.
struct LocatorMark: Identifiable {
    let id = UUID()
    let acuId: String            // atlas id (for colour + tapped-point highlight)
    let label: String            // "EX-HN3 · 印堂"
    let point: CGPoint           // normalized, TOP-LEFT origin, already mirrored to match the preview
}

// Map a normalized (top-left) point through the preview's aspect-fill crop, so a marker lands on the
// same pixels the user sees (mirrors ARCoachView.mapFill).
func locatorMapFill(_ n: CGPoint, in size: CGSize, frameAspect: CGFloat) -> CGPoint {
    let fw = frameAspect, fh: CGFloat = 1
    let s = max(size.width / fw, size.height / fh)
    let dw = s * fw, dh = s * fh
    return CGPoint(x: (size.width - dw) / 2 + n.x * dw, y: (size.height - dh) / 2 + n.y * dh)
}

// Exact inverse of locatorMapFill: a screen point (aspect-fill preview) → normalized TOP-LEFT. The M3
// label harness uses it to turn an expert's tap into a label in the SAME normalized space that
// weightedTarget outputs and the head trains on — so there is no reprojection error in the label.
func locatorInverseFill(_ p: CGPoint, in size: CGSize, frameAspect: CGFloat) -> CGPoint {
    let fw = frameAspect, fh: CGFloat = 1
    let s = max(size.width / fw, size.height / fh)
    let dw = s * fw, dh = s * fh
    return CGPoint(x: (p.x - (size.width - dw) / 2) / dw, y: (p.y - (size.height - dh) / 2) / dh)
}

// Glowing markers + labels over a live camera preview; the tapped point (`focusId`) is enlarged.
struct LocatorMarkersOverlay: View {
    let marks: [LocatorMark]
    let frameAspect: CGFloat
    let focusId: String

    var body: some View {
        GeometryReader { geo in
            ForEach(marks) { m in
                marker(m).position(locatorMapFill(m.point, in: geo.size, frameAspect: frameAspect))
            }
        }
    }

    @ViewBuilder private func marker(_ m: LocatorMark) -> some View {
        let col = MeridianColors.color(Acupoint.byId[m.acuId]?.meridian ?? "extra")
        let hot = m.acuId == focusId
        ZStack {
            Circle().fill(col.opacity(hot ? 0.9 : 0.55))
                .frame(width: hot ? 20 : 13, height: hot ? 20 : 13)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: col.opacity(0.8), radius: 6)
            Text(m.label).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.5)))
                .offset(y: hot ? 22 : 18)
        }
        .accessibilityLabel(m.label)
    }
}
