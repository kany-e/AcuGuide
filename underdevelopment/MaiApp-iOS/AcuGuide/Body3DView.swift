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
    struct Label: Identifiable { let id: String; let region: BodyAtlas.Region; let point: CGPoint }
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
    @State private var pulse = false

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
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            chrome

            if let pt = model.selectedPoint { pointPanel(pt) }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
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

    // Safe-area-respecting controls: a back button when zoomed, else a hint line.
    private var chrome: some View {
        VStack {
            if model.focused != nil {
                HStack {
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
                    Spacer()
                }
                .padding(.horizontal).padding(.top, 6)
            }
            Spacer()
            if let f = model.focused {
                Text(AppLocale.pick(f.zh, f.en)).font(.title3).bold().foregroundStyle(Ink.brush)
                Text(AppLocale.pick("此区域本版本暂无可练习的穴位。",
                                    "No practice points in this region in this build."))
                    .font(.caption).foregroundStyle(Ink.textDim)
                    .multilineTextAlignment(.center).padding(.horizontal)
                    .padding(.bottom, 26)
            } else {
                Text(AppLocale.pick("点按区域放大 · 拖动旋转", "Tap a region to zoom · drag to rotate"))
                    .font(.caption).foregroundStyle(Ink.text.opacity(0.7)).padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder private func regionLabel(_ r: BodyAtlas.Region) -> some View {
        Button { model.tap(r) } label: {
            if r.isHand {
                // The pulsing gold hand hotspot (web HandHotspot) — small, always reachable.
                HStack(spacing: 4) {
                    Circle().fill(Ink.gold).frame(width: 9, height: 9).scaleEffect(pulse ? 1.3 : 0.85)
                    Text(AppLocale.pick(r.zh, r.en)).font(.caption2).bold().foregroundStyle(Ink.gold)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Ink.paperLight.opacity(0.82)))
            } else {
                // Brush-calligraphy ink name tag (Ma Shan Zheng) + a soft parchment halo.
                Text(AppLocale.pick(r.zh, r.en))
                    .font(Typo.brush(19))
                    .foregroundStyle(Ink.brush)
                    .shadow(color: Ink.paperLight.opacity(0.95), radius: 1.6)
                    .shadow(color: Ink.paperLight.opacity(0.7), radius: 0.6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(AppLocale.pick(r.zh, r.en))
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
                    mesh.addChildNode(BodyAtlas.channels())    // meridian channels (skeleton-routed)
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
        var radius: Float = 1
        private var anchors: [(BodyAtlas.Region, SCNNode)] = []
        private var link: CADisplayLink?

        init(model: AtlasModel) { self.model = model; super.init() }

        func attach(view: SpinSCNView, spin: SCNNode) {
            self.view = view; self.spin = spin
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func installBody(cam: SCNNode, radius: Float, anchorsOn mesh: SCNNode) {
            self.cam = cam; self.radius = radius
            anchors = BodyAtlas.regions.map { r in
                let n = SCNNode(); n.simdPosition = r.anchor; mesh.addChildNode(n)
                return (r, n)
            }
        }

        // Project each region anchor to a screen point each frame so the brush labels track the
        // rotating body. Body regions hide on the far side; the hand hotspot stays reachable.
        @objc private func tick() {
            guard let view = view, model.focused == nil, !anchors.isEmpty else {
                if !model.labels.isEmpty && model.focused != nil { model.labels = [] }
                return
            }
            var out: [AtlasModel.Label] = []
            for (r, node) in anchors {
                let wp = node.presentation.worldPosition
                let p = view.projectPoint(wp)
                let onScreen = p.z > 0 && p.z < 1
                let facing = r.isHand || wp.z > -0.01            // camera looks down +z toward origin
                if onScreen && facing {
                    out.append(.init(id: r.id, region: r, point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))))
                }
            }
            model.labels = out
        }

        // Square the body to the front, stop the spin, and dolly the camera in on the region.
        func focus(_ r: BodyAtlas.Region) {
            guard let spin = spin, let cam = cam,
                  let node = anchors.first(where: { $0.0.id == r.id })?.1 else { return }
            let pres = spin.presentation.eulerAngles
            spin.removeAllActions()
            spin.eulerAngles = SCNVector3Zero                    // read the front-facing anchor pos
            let target = node.worldPosition
            spin.eulerAngles = pres                              // restore for a smooth animation
            model.labels = []
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            spin.eulerAngles = SCNVector3Zero
            cam.position = SCNVector3(target.x, target.y, target.z + radius * 2.4)
            cam.eulerAngles = SCNVector3Zero
            SCNTransaction.commit()
        }

        func unfocus() {
            guard let spin = spin, let cam = cam else { return }
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            cam.position = SCNVector3(0, 0, radius * 11)
            cam.eulerAngles = SCNVector3Zero
            SCNTransaction.commit()
            spin.eulerAngles = SCNVector3Zero
            spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))
        }

        // Hit-test a tap against the acupoint marker nodes (named "acu:<id>").
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name, name.hasPrefix("acu:") {
                        let id = String(name.dropFirst(4))
                        if let pt = Acupoint.all.first(where: { $0.id == id }) { model.selectedPoint = pt }
                        return
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
    m.transparency = 0.85               // a little see-through
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
