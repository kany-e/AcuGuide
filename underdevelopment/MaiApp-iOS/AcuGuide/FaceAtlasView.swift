import AVFoundation
import Vision
import SwiftUI

// Front-camera face acupoint locator. Runs VNDetectFaceLandmarksRequest and marks the visible head
// points (Yintang / Taiyang) on the live, mirrored selfie preview via FaceAcupoints — the face
// counterpart to the hand AR coach. This is a LOCATOR (shows where the points are on YOU); the
// press-and-hold coaching layer is hand-only for now.
final class FaceCamera: LocatorCameraBase {
    private let request = VNDetectFaceLandmarksRequest()

    override func detect(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation, aspect: CGFloat) -> [LocatorMark] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
        try? handler.perform([request])
        let face = (request.results as? [VNFaceObservation])?.first
        return face.map { FaceAcupoints.marks(from: $0, mirrored: mirrored) } ?? []
    }
}

struct FaceAtlasView: View {
    let focus: Acupoint                  // the tapped head point (title + highlight)
    var onClose: () -> Void
    @StateObject private var camera = FaceCamera()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session, mirrored: camera.mirrored)
                    .ignoresSafeArea().accessibilityHidden(true)
                LocatorMarkersOverlay(marks: camera.marks, frameAspect: camera.frameAspect, focusId: focus.id)
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
}
