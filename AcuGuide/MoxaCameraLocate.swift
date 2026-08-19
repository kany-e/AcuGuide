import AVFoundation
import Vision
import SwiftUI

// "Show me on my own body" for the abdominal moxa points.
//
// Body pose → the proportional-cun midline (MoxaTorsoAcupoints) → Shenque, Qihai and Guanyuan
// marked on the live mirrored preview. A LOCATOR, never a coach: nothing here times anything, and
// nothing here decides that a box may go on. The skin-check clock is the next step and it is the
// one that holds the safety rules.
//
// WHY IT SHOWS ALL THREE AND NOT JUST THE ONE YOU TAPPED. On this span the neighbours are the
// sanity check: Shenque sits AT the navel and Guanyuan at 0.60 of the way to the pubic border, so
// seeing them bracket Qihai is how a user notices the frame is wrong. It is also the honest picture
// of the thing the placement copy warns about — the three sit on one line, close enough that a box
// covers a stretch of it rather than a point.
final class MoxaTorsoCamera: LocatorCameraBase {
    private let request = VNDetectHumanBodyPoseRequest()

    override func detect(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation,
                         aspect: CGFloat) -> [LocatorMark] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
        try? handler.perform([request])
        return request.results?.first.map {
            MoxaTorsoAcupoints.marks(from: $0, aspect: aspect, mirrored: mirrored)
        } ?? []
    }
}

struct MoxaCameraLocateView: View {
    let focus: MoxaPoint
    var onClose: () -> Void
    @StateObject private var camera = MoxaTorsoCamera()

    var body: some View {
        NavigationStack {
            CameraGate(onAuthorized: { camera.start() }) { ZStack {
                Color.black.ignoresSafeArea()
                CameraPreview(session: camera.session, mirrored: camera.mirrored)
                    .ignoresSafeArea().accessibilityHidden(true)
                LocatorMarkersOverlay(marks: camera.marks, frameAspect: camera.frameAspect,
                                      focusId: focus.id)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(camera.marks.isEmpty ? MoxaLocateCopy.frameYourself
                                                  : MoxaLocateCopy.marksAreProportional)
                            .font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                        Text(MoxaLocateCopy.cameraEstimate)
                            .font(.caption2).foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        Text(MoxaLocateCopy.cameraNotAGo)
                            .font(.caption2).foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.45)))
                    .padding().padding(.bottom, 8)
                }
            } }
            .navigationTitle(AppLocale.pick("在身上找 · \(focus.zh)", "On your body · \(focus.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { onClose() }.tint(Ink.gold)
            } }
        }
        .onDisappear { camera.stop() }   // start happens via CameraGate.onAuthorized
    }
}

// Every string the locate step shows, in one enumerable place — the claims scans walk `allCopy`,
// and a string a view renders that the scan cannot reach is an unscanned surface.
enum MoxaLocateCopy {
    static var frameYourself: String {
        AppLocale.pick("躺下或靠坐，让脖子到胯部都在画面里。",
                       "Lie down or sit back, with everything from your neck to your hips in frame.")
    }
    static var marksAreProportional: String {
        AppLocale.pick("这三处按你自己的身体比例标出（画面是镜像的）。",
                       "The three places are marked by your own body's proportions (the picture is mirrored).")
    }
    static var cameraEstimate: String {
        AppLocale.pick("腹部是软组织，相机给的是按“寸”比例的估算，比自己用手指量更粗，用来对照，不要用来代替。",
                       "The abdomen is soft tissue, so the camera gives a proportional estimate — rougher than measuring with your own fingers. Use it to check that measurement, not to replace it.")
    }
    static var cameraNotAGo: String {
        AppLocale.pick("相机只是帮你找位置，不判断能不能灸、也不计时。",
                       "The camera only helps you find the place. It does not decide whether to go ahead, and it does not keep time.")
    }
    static var allCopy: [String] { [frameYourself, marksAreProportional, cameraEstimate, cameraNotAGo] }
}
