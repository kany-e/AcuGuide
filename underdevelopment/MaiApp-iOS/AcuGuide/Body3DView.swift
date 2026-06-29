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
    fileprivate weak var coordinator: SceneKitBody.Coordinator?

    func tap(_ region: BodyAtlas.Region, onEnterHand: () -> Void) {
        if region.isHand { onEnterHand(); return }   // hand is the drill-down, not a zoom
        focused = region
        coordinator?.focus(region)
    }
    func exitFocus() { focused = nil; coordinator?.unfocus() }
}

struct Body3DView: View {
    var onEnterHand: () -> Void = {}
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
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    // Safe-area-respecting controls: a back button when zoomed, else a hint line.
    private var chrome: some View {
        VStack {
            if let f = model.focused {
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
        Button { model.tap(r, onEnterHand: onEnterHand) } label: {
            if r.isHand {
                // The pulsing gold hand hotspot (web HandHotspot) — small, always reachable.
                HStack(spacing: 4) {
                    Circle().fill(Ink.gold).frame(width: 9, height: 9).scaleEffect(pulse ? 1.3 : 0.85)
                    Text(AppLocale.pick(r.zh, r.en)).font(.caption2).bold().foregroundStyle(Ink.gold)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Ink.paperLight.opacity(0.82)))
            } else {
                // Brush-style ink name tag — plain text + a soft parchment halo for legibility.
                Text(AppLocale.pick(r.zh, r.en))
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(Ink.brush)
                    .shadow(color: Ink.paperLight.opacity(0.95), radius: 1.6)
                    .shadow(color: Ink.paperLight.opacity(0.7), radius: 0.6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(AppLocale.pick(r.zh, r.en))
        .accessibilityHint(r.isHand ? AppLocale.pick("查看手部穴位", "Opens the hand acupoint map")
                                    : AppLocale.pick("放大到此区域", "Zooms to this region"))
    }
}

struct SceneKitBody: UIViewRepresentable {
    @ObservedObject var model: AtlasModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SpinSCNView {
        let view = SpinSCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        let spin = SCNNode()                                   // auto-rotation container
        scene.rootNode.addChildNode(spin)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))

        let capsule = makeCapsule()                            // placeholder until the GLB loads
        spin.addChildNode(capsule)

        view.scene = scene
        view.spinNode = spin
        context.coordinator.attach(view: view, spin: spin)
        model.coordinator = context.coordinator

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

        func stop() { link?.invalidate(); link = nil }
    }
}

// MARK: - Scene helpers (match Body3D.jsx's feel)

// Sage-green matte material (#aebd9d, low emissive), slightly translucent — matches Body3D.jsx's
// roughness 0.85 / transparency feel. .blinn (not PBR, which washes white without an env map).
private func sageMaterial() -> SCNMaterial {
    let mat = SCNMaterial()
    mat.lightingModel = .blinn
    mat.diffuse.contents = UIColor(Ink.bodySage)
    mat.specular.contents = UIColor(white: 1, alpha: 0.0)
    mat.emission.contents = UIColor(Ink.bodyEmission).withAlphaComponent(0.12)
    mat.transparency = 0.85
    mat.isDoubleSided = true
    return mat
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
