import AVFoundation
import Vision
import SwiftUI

// Front-camera torso/abdomen locator: body pose → proportional-cun midline → marks CV12 / ST25 on
// the live mirrored preview via TorsoAcupoints. Locator only (no press coaching). Frame yourself so
// your neck and hips are both in view.
final class TorsoCamera: LocatorCameraBase {
    private let request = VNDetectHumanBodyPoseRequest()

    override func detect(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation, aspect: CGFloat) -> [LocatorMark] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
        try? handler.perform([request])
        let body = (request.results as? [VNHumanBodyPoseObservation])?.first
        return body.map { TorsoAcupoints.marks(from: $0, aspect: aspect, mirrored: mirrored) } ?? []
    }
}

struct TorsoAtlasView: View {
    let focus: Acupoint
    var onClose: () -> Void
    @StateObject private var camera = TorsoCamera()

    var body: some View {
        NavigationStack {
            CameraGate(onAuthorized: { camera.start() }) { ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session, mirrored: camera.mirrored)
                    .ignoresSafeArea().accessibilityHidden(true)
                LocatorMarkersOverlay(marks: camera.marks, frameAspect: camera.frameAspect, focusId: focus.id)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(camera.marks.isEmpty
                             ? AppLocale.pick("让上身入镜 — 颈部到髋部都要在画面中。",
                                              "Frame your upper body — neck to hips both in view.")
                             : AppLocale.pick("穴位已按比例标注在你身上（镜像）。",
                                              "Points are marked on you by proportion (mirrored)."))
                            .font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                        Text(AppLocale.pick("腹部为软组织，定位为按“寸”比例的估算，误差较大。",
                                            "The abdomen is soft tissue — placement is a proportional (cun) estimate and coarse."))
                            .font(.caption2).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                        Text(AppLocale.pick("仅供养生自我保养参考。", "Wellness self-care only."))
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4)))
                    .padding().padding(.bottom, 8)
                }
            } }
            .navigationTitle(AppLocale.pick("身体定位 · \(focus.zh)", "On your body · \(focus.en)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { onClose() }.tint(Ink.gold)
            } }
        }
        .onDisappear { camera.stop() }   // start happens via CameraGate.onAuthorized
    }
}
