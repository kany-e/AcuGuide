import AVFoundation
import Vision
import SwiftUI

// Front-camera face acupoint locator. Runs VNDetectFaceLandmarksRequest and marks the visible head
// points (Yintang / Taiyang) on the live, mirrored selfie preview via FaceAcupoints — the face
// counterpart to the hand AR coach. This is a LOCATOR (shows where the points are on YOU); the
// press-and-hold coaching layer is hand-only for now.
final class FaceCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var marks: [FaceAcupoints.Mark] = []
    @Published var frameAspect: CGFloat = 9.0 / 16.0
    let mirrored = true                       // front camera → mirrored selfie preview

    private var lastAspect: CGFloat = 0
    private let queue = DispatchQueue(label: "face.camera")
    private let request = VNDetectFaceLandmarksRequest()
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
            conn.forcePortrait()              // upright buffers → landmark coords share the overlay space
            conn.setMirrored(false)           // data un-mirrored; the PREVIEW mirrors; marks flip x
        }
        session.commitConfiguration()
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    // Same connection-derived orientation as the hand path (portrait configured → .up).
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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        let aspect = CGFloat(min(w, h)) / CGFloat(max(w, h))
        if abs(aspect - lastAspect) > 0.001 { lastAspect = aspect; DispatchQueue.main.async { self.frameAspect = aspect } }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: visionOrientation(), options: [:])
        try? handler.perform([request])
        let face = (request.results as? [VNFaceObservation])?.first
        let marks = face.map { FaceAcupoints.marks(from: $0, mirrored: mirrored) } ?? []
        DispatchQueue.main.async { self.marks = marks }
    }
}

struct FaceAtlasView: View {
    let focus: Acupoint                  // the tapped head point (title + highlight)
    var onClose: () -> Void
    @StateObject private var camera = FaceCamera()

    // Map a normalized (top-left) point through the preview's aspect-fill crop (mirrors ARCoachView).
    private func mapFill(_ n: CGPoint, _ size: CGSize) -> CGPoint {
        let fw = camera.frameAspect, fh: CGFloat = 1
        let s = max(size.width / fw, size.height / fh)
        let dw = s * fw, dh = s * fh
        let ox = (size.width - dw) / 2, oy = (size.height - dh) / 2
        return CGPoint(x: ox + n.x * dw, y: oy + n.y * dh)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { geo in
                    ZStack {
                        CameraPreview(session: camera.session, mirrored: camera.mirrored)
                            .accessibilityHidden(true)
                        ForEach(camera.marks) { m in marker(m).position(mapFill(m.point, geo.size)) }
                    }
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        if camera.marks.isEmpty {
                            Text(AppLocale.pick("把脸对准前置相机。", "Bring your face into the front camera."))
                                .font(.subheadline).foregroundStyle(.white)
                        } else {
                            Text(AppLocale.pick("穴位已标注在你的脸上（镜像）。",
                                                "Points are marked on your face (mirrored)."))
                                .font(.subheadline).foregroundStyle(.white)
                        }
                        Text(AppLocale.pick("百会、四神聪在头顶，正面相机看不到。",
                                            "Baihui & Sishencong are on the crown — not visible to a front camera."))
                            .font(.caption2).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                        Text(AppLocale.pick("定位为估算，仅供养生自我保养参考。",
                                            "Placement is approximate — wellness self-care only."))
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4)))
                    .padding().padding(.bottom, 8)
                }
            }
            .navigationTitle(AppLocale.pick("面部定位 · \(focus.zh)", "On your face · \(focus.en)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { onClose() }.tint(Ink.gold)
            } }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder private func marker(_ m: FaceAcupoints.Mark) -> some View {
        let col = MeridianColors.color(Acupoint.byId[m.acuId]?.meridian ?? "extra")
        let hot = m.acuId == focus.id
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
