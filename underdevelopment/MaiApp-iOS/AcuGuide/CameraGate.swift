import SwiftUI
import AVFoundation

// Camera-permission gate wrapping every camera surface (AR coach, face/torso locators, label capture).
// Before this, a declined permission left a silent black screen forever — an App-Review-visible dead
// end. States: notDetermined → a plain-language explainer with an Enable button (so the system prompt
// arrives in context, not cold); denied/restricted → an open-Settings hand-off; authorized → the
// wrapped content, with `onAuthorized` fired on appearance (start the capture session there — session
// starts are idempotent). The atlas/chat remain fully usable without ever granting the camera.
struct CameraGate<Content: View>: View {
    var onAuthorized: () -> Void = {}
    // Optional camera-free escape: hosts that HAVE a no-camera equivalent (the coach → guided
    // timer) surface it on the permission screens, so a denied camera never dead-ends a session
    // or a routine step. Locators (face/torso) have no equivalent and leave it nil.
    var onUseTimer: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        switch status {
        case .authorized:
            content().onAppear(perform: onAuthorized)
        case .notDetermined:
            prompt(
                icon: "camera.viewfinder",
                title: AppLocale.pick("需要使用相机", "Camera needed"),
                text: AppLocale.pick(
                    "画面仅在设备上实时处理，用于标注穴位位置 — 不会保存，也不会上传。",
                    "Frames are processed live on this device to mark point locations — never stored, never uploaded."),
                button: AppLocale.pick("启用相机", "Enable camera")) {
                    AVCaptureDevice.requestAccess(for: .video) { ok in
                        DispatchQueue.main.async { status = ok ? .authorized : .denied }
                    }
                }
        default:
            prompt(
                icon: "camera.on.rectangle",
                title: AppLocale.pick("相机权限已关闭", "Camera access is off"),
                text: AppLocale.pick(
                    "在系统设置中允许 AcuGuide 使用相机后，\(CoachPersona.name) 才能在画面里陪你练。图谱与问答无需相机。",
                    "Allow AcuGuide to use the camera in Settings so \(CoachPersona.name) can coach you on screen. The atlas and chat work without it."),
                button: AppLocale.pick("打开设置", "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
        }
    }

    private func prompt(icon: String, title: String, text: String,
                        button: String, action: @escaping () -> Void) -> some View {
        // Self-contained ground: some hosts (face/torso locators) sit on black, where Ink text
        // would be unreadable.
        ZStack {
            ShanshuiBackground()
            VStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 42)).foregroundStyle(Ink.gold)
                Text(title).font(Typo.serif(20, weight: .semibold)).foregroundStyle(Ink.gold)
                Text(text).font(.subheadline).foregroundStyle(Ink.text)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
                Button(button, action: action).buttonStyle(GoldButtonStyle())
                if let onUseTimer {
                    Button(AppLocale.pick("不用相机 · 计时引导", "Use the guided timer instead")) { onUseTimer() }
                        .font(.subheadline).tint(Ink.gold)
                }
            }
            .padding(28)
        }
        // Re-check when returning from Settings (the app foregrounds again).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
}
