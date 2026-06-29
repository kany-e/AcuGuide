import SwiftUI
import SceneKit
import GLTFKit2
import simd

// Rotatable 3D body — native port of MaiApp's Body3D.jsx. Loads the SAME asset as the web app,
// model.glb, at runtime via GLTFKit2 (no usdz / no drift). Sage-green matte material, soft
// lighting, gentle auto-rotate, meridian channels along the skeleton, and brush-style region
// labels (头/胸/腹/臂/腿/足/手部) projected onto the body. Tapping a body region zooms the camera
// in to that part (a 全身/Full-body control returns); tapping 手部 drills into the hand acupoint
// map (mirrors the web onEnterHand). The capsule shows only if the model is missing.

// Shared state between the SwiftUI overlay and the SceneKit coordinator.
final class AtlasModel: ObservableObject {
    struct Label: Identifiable { let id: String; let region: BodyAtlas.Region; let point: CGPoint; let opacity: Double }
    @Published var labels: [Label] = []          // region labels projected to screen (full-body mode)
    @Published var focused: BodyAtlas.Region?    // non-nil while zoomed into a region
    @Published var selectedPoint: Acupoint?      // a tapped 3D acupoint marker
    fileprivate weak var coordinator: SceneKitBody.Coordinator?

    // Every region (including the hand) is now an IN-SCENE camera zoom — no 2D drill-down.
    func tap(_ region: BodyAtlas.Region) {
        selectedPoint = nil
        focused = region
        coordinator?.focus(region)
    }
    func exitFocus() { focused = nil; selectedPoint = nil; coordinator?.unfocus() }
}

struct Body3DView: View {
    var onPractice: (Acupoint) -> Void = { _ in }   // TE3 marker → launch the AR coach
    @StateObject private var model = AtlasModel()
    @ObservedObject private var settings = AppSettings.shared   // re-render labels on language toggle
    @State private var showSettings = false
    @State private var showHandChart = false        // 2D finger-detail fallback for the hand region
    @State private var handChartCoach: Acupoint? = nil

    var body: some View {
        ZStack {
            ShanshuiBackground()
            SceneKitBody(model: model).ignoresSafeArea().accessibilityHidden(true)

            // Region labels projected onto the body (full-body mode only). This overlay is
            // full-screen + ignoresSafeArea so .position matches SceneKit's projectPoint coords.
            ZStack {
                if model.focused == nil {
                    ForEach(model.labels) { lab in
                        regionLabel(lab.region).position(lab.point)
                            .opacity(lab.opacity)
                            .allowsHitTesting(lab.opacity > 0.35)   // don't tap a near-faded label
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            chrome

            if let pt = model.selectedPoint { pointPanel(pt) }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showHandChart) {
            // The 3D hand is a low-poly mitten; this 2D silhouette (HAND_PTS) has real fingers and
            // legible point placement — the spec-sanctioned inset fallback for the hand region.
            NavigationStack {
                HandAtlasView(startCoach: $handChartCoach)
                    .navigationTitle(AppLocale.pick("手部穴位", "Hand points"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocale.pick("完成", "Done")) { showHandChart = false }.tint(Ink.gold)
                    } }
            }
            .onChange(of: handChartCoach) { v in
                if let pt = v { showHandChart = false; handChartCoach = nil; onPractice(pt) }
            }
        }
    }

    // Tapped-marker detail card (bottom). TE3 keeps the validated "Practice with camera" path.
    private func pointPanel(_ pt: Acupoint) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 10, height: 10)
                    Text("\(pt.id) · \(pt.zh)").font(Typo.serif(18, weight: .semibold)).foregroundStyle(Ink.gold)
                    Text(pt.en).font(Typo.code(17)).foregroundStyle(Ink.textDim)
                    Spacer()
                    Button { model.selectedPoint = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.textDim)
                    }.accessibilityLabel(AppLocale.pick("关闭", "Close"))
                }
                Text(pt.location).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                if pt.mediapipeTarget != nil {
                    Button(AppLocale.pick("用相机练习", "Practice with camera")) {
                        let p = pt; model.selectedPoint = nil; onPractice(p)
                    }.buttonStyle(GoldButtonStyle())
                } else {
                    Text(AppLocale.pick("本版本仅 TE3 提供相机引导。",
                                        "Camera coaching is available for TE3 in this build."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().panel().padding()
        }
        .transition(.move(edge: .bottom))
    }

    // Safe-area-respecting controls: a top bar (back when zoomed, gear always) + a bottom hint.
    private var chrome: some View {
        VStack {
            HStack {
                if model.focused != nil {
                    Button { model.exitFocus() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left").font(.caption.bold())
                            Text(AppLocale.pick("全身", "Full body")).font(.subheadline).bold()
                        }
                        .foregroundStyle(Ink.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Ink.paperLight).overlay(Capsule().stroke(Ink.line, lineWidth: 1)))
                    }
                    .accessibilityLabel(AppLocale.pick("返回全身", "Back to full body"))
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.callout).foregroundStyle(Ink.text)
                        .padding(9)
                        .background(Circle().fill(Ink.paperLight).overlay(Circle().stroke(Ink.line, lineWidth: 1)))
                }
                .accessibilityLabel(AppLocale.pick("设置", "Settings"))
            }
            .padding(.horizontal).padding(.top, 6)
            Spacer()
            if let f = model.focused {
                Text(AppLocale.pick(f.zh, f.en)).font(Typo.brush(30)).foregroundStyle(Ink.brush)
                if f.isHand {
                    Text(AppLocale.pick("点按 3D 穴位，或查看带手指的手部图。",
                                        "Tap a 3D point, or open the finger-detail hand chart."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button(AppLocale.pick("手部图", "Hand chart")) { showHandChart = true }
                        .buttonStyle(GoldButtonStyle()).padding(.top, 2).padding(.bottom, 16)
                } else {
                    Text(AppLocale.pick("此区域本版本暂无可练习的穴位。", "No practice points in this region in this build."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .multilineTextAlignment(.center).padding(.horizontal)
                        .padding(.bottom, 26)
                }
            } else {
                Text(AppLocale.pick("点按区域放大 · 拖动旋转", "Tap a region to zoom · drag to rotate"))
                    .font(.caption).foregroundStyle(Ink.text.opacity(0.7)).padding(.bottom, 24)
            }
        }
    }

    // Every region — the hand included — uses the same brush label; it enlarges + glows gold on
    // hover/press and zooms on tap.
    @ViewBuilder private func regionLabel(_ r: BodyAtlas.Region) -> some View {
        BrushLabel(text: AppLocale.pick(r.zh, r.en)) { model.tap(r) }
            .accessibilityHint(AppLocale.pick("放大到此区域并显示穴位", "Zooms in and shows its acupoints"))
    }
}

struct SceneKitBody: UIViewRepresentable {
    @ObservedObject var model: AtlasModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SpinSCNView {
        let view = SpinSCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false   // its omni light glosses the body; light softly instead
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        addSoftLighting(to: scene)                // ambient + low fill, no bright directional
        let spin = SCNNode()                                   // auto-rotation container
        scene.rootNode.addChildNode(spin)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))

        let capsule = makeCapsule()                            // placeholder until the GLB loads
        spin.addChildNode(capsule)

        view.scene = scene
        view.spinNode = spin
        context.coordinator.attach(view: view, spin: spin)
        model.coordinator = context.coordinator

        // Tap to select a 3D acupoint marker (coexists with allowsCameraControl's pan/pinch).
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        if let url = Bundle.main.url(forResource: "model", withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltfScene = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    // GLTFKit2's skinner collapses the rigged mesh to a point; render the static
                    // bind-pose geometry directly. Authored Z-up (lying down) → -90°X stands it up.
                    var found: SCNGeometry? = nil
                    gltfScene.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
                    guard let found else { return }
                    capsule.removeFromParentNode()
                    let geometry = found.copy() as! SCNGeometry
                    geometry.materials = [sageMaterial()]
                    let mesh = SCNNode(geometry: geometry)
                    let (lo, hi) = mesh.boundingBox
                    mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
                    mesh.addChildNode(BodyAtlas.channels(on: mesh))  // meridian channels (skeleton-routed, surface-projected)
                    mesh.addChildNode(BodyAtlas.markers())     // 3D acupoint markers (hand/forearm)
                    let pose = SCNNode()
                    pose.addChildNode(mesh)
                    pose.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                    spin.addChildNode(pose)

                    // Explicit camera (root child) so allowsCameraControl's auto-fit doesn't reframe
                    // the figure to fill the view; placed back so it reads as a small ink figure.
                    let radius = pose.boundingSphere.radius
                    let cam = SCNNode()
                    cam.camera = SCNCamera()
                    cam.camera?.fieldOfView = 50
                    cam.camera?.zNear = 0.01
                    cam.camera?.zFar = Double(radius) * 400 + 100
                    cam.position = SCNVector3(0, 0, radius * 11)
                    scene.rootNode.addChildNode(cam)
                    view.pointOfView = cam

                    context.coordinator.installBody(cam: cam, radius: radius, anchorsOn: mesh)
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: SpinSCNView, context: Context) {}
    static func dismantleUIView(_ uiView: SpinSCNView, coordinator: Coordinator) { coordinator.stop() }

    // Drives per-frame projection of region anchors to screen + camera zoom-to-region.
    final class Coordinator: NSObject {
        let model: AtlasModel
        weak var view: SpinSCNView?
        weak var spin: SCNNode?
        weak var cam: SCNNode?
        weak var mesh: SCNNode?
        var radius: Float = 1
        private var anchors: [(BodyAtlas.Region, SCNNode)] = []
        private var link: CADisplayLink?
        private var lastPublish: CFTimeInterval = 0

        init(model: AtlasModel) { self.model = model; super.init() }

        func attach(view: SpinSCNView, spin: SCNNode) {
            self.view = view; self.spin = spin
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func installBody(cam: SCNNode, radius: Float, anchorsOn mesh: SCNNode) {
            self.cam = cam; self.radius = radius
            self.mesh = mesh
            anchors = BodyAtlas.regions.map { r in
                let n = SCNNode(); n.simdPosition = r.anchor; mesh.addChildNode(n)
                return (r, n)
            }
            // Orbit pinch/drag around the body center (origin) in full-body mode, so manual zoom
            // keeps the figure framed instead of dollying toward the scene origin and sliding off.
            view?.defaultCameraController.target = SCNVector3Zero
        }

        // Project each region anchor to a screen point each frame so the brush labels track the
        // rotating body. Body regions hide on the far side; the hand hotspot stays reachable.
        @objc private func tick() {
            guard let view = view, model.focused == nil, !anchors.isEmpty else {
                if !model.labels.isEmpty && model.focused != nil { model.labels = [] }
                return
            }
            // Throttle the @Published label republish to ~30 Hz so the overlay isn't diffed at the
            // full 60–120 Hz display rate the whole time the auto-rotating atlas is on screen.
            let now = link?.timestamp ?? 0
            if now - lastPublish < 1.0 / 30.0 { return }
            lastPublish = now
            var out: [AtlasModel.Label] = []
            for (r, node) in anchors {
                let wp = node.presentation.worldPosition
                let p = view.projectPoint(wp)
                guard p.z > 0 && p.z < 1 else { continue }       // off-screen / behind camera
                // Fade by facing instead of a hard cut, so labels don't pop in/out as the body
                // rotates: full opacity on the near side, ramping to 0 as the anchor turns away.
                // The hand stays fully visible (it's the key drill-down).
                let z = Float(wp.z)
                let opacity = r.isHand ? 1.0 : Double(max(0, min(1, (z + 0.05) / 0.09)))
                if opacity > 0.02 {
                    out.append(.init(id: r.id, region: r,
                                     point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), opacity: opacity))
                }
            }
            model.labels = out
        }

        // Square the body to the front, stop the spin, and dolly the camera in so the PART itself
        // fills the view (distance from the region's own extent, not the whole-body radius).
        func focus(_ r: BodyAtlas.Region) {
            guard let spin = spin, let cam = cam, let mesh = mesh else { return }
            let pres = spin.presentation.eulerAngles
            spin.removeAllActions()
            spin.eulerAngles = SCNVector3Zero                    // read the front-facing region center
            let target = mesh.convertPosition(SCNVector3(r.center.x, r.center.y, r.center.z), to: nil)
            spin.eulerAngles = pres                              // restore for a smooth animation
            model.labels = []
            // distance = regionRadius / tan(fov/2) * margin → the part fills ~70% of the view.
            let fovHalf = Float(25.0 * Double.pi / 180.0)        // camera fov is 50°
            let dist = r.radius / tan(fovHalf) * 1.3
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            spin.eulerAngles = SCNVector3Zero
            cam.position = SCNVector3(target.x, target.y, target.z + dist)
            cam.eulerAngles = SCNVector3Zero
            SCNTransaction.commit()
            // Orbit the focused part: pinch/drag now zoom around it, not the scene origin.
            view?.defaultCameraController.target = target
        }

        func unfocus() {
            guard let spin = spin, let cam = cam else { return }
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            cam.position = SCNVector3(0, 0, radius * 11)
            cam.eulerAngles = SCNVector3Zero
            SCNTransaction.commit()
            view?.defaultCameraController.target = SCNVector3Zero    // recenter the orbit pivot
            spin.eulerAngles = SCNVector3Zero
            spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))
        }

        // Hit-test a tap against the acupoint marker nodes (named "acu:<id>"). Markers draw with
        // depth-test off (always on top), so a far-side marker can sit under the tap — only accept
        // one on the camera-facing side (z > 0), the nearest hit first.
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name, name.hasPrefix("acu:") {
                        if node.presentation.worldPosition.z > -0.02 {     // facing the camera
                            let id = String(name.dropFirst(4))
                            if let pt = Acupoint.all.first(where: { $0.id == id }) { model.selectedPoint = pt }
                            return
                        }
                    }
                    n = node.parent
                }
            }
        }

        func stop() { link?.invalidate(); link = nil }
    }
}

// MARK: - Scene helpers (match Body3D.jsx's feel)

// Fully MATTE sage body (no specular highlight), slightly translucent — per the round-2 note.
// PBR with roughness 1 / metalness 0 / clearCoat 0 has no glossy hotspot; combined with the soft
// ambient+fill lighting (and default lighting OFF) it reads as flat ink, not shiny plastic.
private func sageMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.metalness.contents = 0.0
    m.roughness.contents = 1.0          // fully matte: no specular hotspot
    m.clearCoat.contents = 0.0
    m.diffuse.contents = UIColor(Ink.bodySage)
    m.emission.contents = UIColor(Ink.bodyEmission)
    m.emission.intensity = 0.12
    m.transparency = 0.92               // a touch see-through, but solid enough that an overlapping
                                        // hand reads against the torso instead of blending in
    m.isDoubleSided = true
    return m
}

// Soft, even lighting (web's ambientLight 0.9 + hemisphereLight feel): a bright ambient plus a
// low warm fill for gentle form — NO bright directional that would re-introduce a highlight.
private func addSoftLighting(to scene: SCNScene) {
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 720
    ambient.light?.color = UIColor(white: 1.0, alpha: 1.0)
    scene.rootNode.addChildNode(ambient)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light?.type = .directional
    fill.light?.intensity = 230
    fill.light?.color = UIColor(Color(hex: "#fffaf0"))
    fill.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 7, 0)   // soft upper-front
    scene.rootNode.addChildNode(fill)
}

private func makeCapsule() -> SCNNode {
    let body = SCNNode(geometry: SCNCapsule(capRadius: 0.4, height: 2.2))
    body.geometry?.firstMaterial?.diffuse.contents = UIColor(Ink.jade)
    body.geometry?.firstMaterial?.emission.contents = UIColor(Ink.gold).withAlphaComponent(0.25)
    return body
}

// Pauses the auto-rotation while the user is interacting, so it never fights the drag.
final class SpinSCNView: SCNView {
    weak var spinNode: SCNNode?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event); spinNode?.isPaused = true
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event); spinNode?.isPaused = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event); spinNode?.isPaused = false
    }
}

// Brush-calligraphy region label (Ma Shan Zheng), uniform across all regions. Enlarges + glows
// gold on hover (pointer) or press (touch); tap fires the zoom action.
struct BrushLabel: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Typo.brush(19))
                .foregroundStyle(Ink.brush)
                .shadow(color: Ink.paperLight.opacity(0.95), radius: 1.6)
                .shadow(color: Ink.paperLight.opacity(0.7), radius: 0.6)
        }
        .buttonStyle(BrushPressStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .accessibilityLabel(text)
    }
}

private struct BrushPressStyle: ButtonStyle {
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        let active = hovering || configuration.isPressed
        return configuration.label
            .scaleEffect(active ? 1.12 : 1.0)
            .shadow(color: Ink.gold.opacity(active ? 0.85 : 0.0), radius: active ? 7 : 0)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}
