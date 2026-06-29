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
    // A floating acupoint name tag drawn at a projected marker position (while a meridian is selected).
    struct PLabel: Identifiable { let id: String; let text: String; let color: Color; let point: CGPoint; let opacity: Double }
    @Published var labels: [Label] = []          // region labels projected to screen (full-body mode)
    @Published var pointLabels: [PLabel] = []    // acupoint name tags for the selected meridian
    @Published var focused: BodyAtlas.Region?    // non-nil while zoomed into a region
    @Published var selectedPoint: Acupoint?      // a tapped 3D acupoint marker
    @Published var selectedMeridian: Meridian?   // a tapped channel → its card + point tags
    fileprivate weak var coordinator: SceneKitBody.Coordinator?

    // Every region (including the hand) is now an IN-SCENE camera zoom — no 2D drill-down.
    func tap(_ region: BodyAtlas.Region) {
        selectedPoint = nil
        selectedMeridian = nil
        pointLabels = []
        focused = region
        coordinator?.focus(region)
    }
    func exitFocus() { focused = nil; selectedPoint = nil; selectedMeridian = nil; pointLabels = []; coordinator?.unfocus() }
    func clearSelection() { selectedPoint = nil; selectedMeridian = nil; pointLabels = [] }
}

struct Body3DView: View {
    var onPractice: (Acupoint) -> Void = { _ in }   // TE3 marker → launch the AR coach
    @StateObject private var model = AtlasModel()
    @ObservedObject private var settings = AppSettings.shared   // re-render labels on language toggle
    @State private var showSettings = false
    @State private var showHandChart = false        // 3D finger-detail hand for the hand region
    @State private var handChartCoach: Acupoint? = nil
    @State private var handSel: Acupoint? = nil      // a tapped marker on the detailed hand chart
    @State private var detailPart: PartDetail? = nil // head/arm/foot detailed-model drill-down

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

            // Acupoint name tags floating on the selected meridian's markers ("their names display
            // as you tap the channel"). Non-interactive — taps still reach the 3D markers/channels.
            ZStack {
                ForEach(model.pointLabels) { lab in
                    pointTag(lab).position(lab.point).opacity(lab.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            chrome

            if let pt = model.selectedPoint { pointPanel(pt) }
            else if let m = model.selectedMeridian { meridianPanel(m) }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showHandChart) {
            // Detailed 3D hand (real fingers) for the hand drill-down — the body's hand is a mitten.
            NavigationStack {
                ZStack {
                    ShanshuiBackground()
                    HandModel3DView(onSelect: { handSel = $0 }).ignoresSafeArea()
                    VStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if let s = handSel {
                                // Tapped-marker detail.
                                HStack(spacing: 8) {
                                    Circle().fill(MeridianColors.color(s.meridian)).frame(width: 9, height: 9)
                                    Text("\(s.id) · \(s.zh)").font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                                    Text(s.en).font(Typo.code(15)).foregroundStyle(Ink.textDim)
                                }
                                Text(s.location).font(.caption).foregroundStyle(Ink.text)
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                if s.mediapipeTarget != nil {
                                    Button(AppLocale.pick("用相机练习", "Practice with camera")) { handChartCoach = s }
                                        .buttonStyle(GoldButtonStyle())
                                }
                            } else {
                                Text(AppLocale.pick("点按手上的穴位查看详情：中渚 TE3 · 后溪 SI3 · 劳宫 PC8 · 神门 HT7",
                                                    "Tap a point on the hand for detail: TE3 · SI3 · PC8 · HT7"))
                                    .font(.caption).foregroundStyle(Ink.text.opacity(0.75))
                                    .multilineTextAlignment(.center)
                                Button(AppLocale.pick("用相机练习 TE3", "Practice TE3 with camera")) {
                                    if let te3 = Acupoint.all.first(where: { $0.id == "TE3" }) { handChartCoach = te3 }
                                }.buttonStyle(GoldButtonStyle())
                            }
                            Text(AppLocale.pick("手部模型 · scribbletoad（CC-BY 4.0）",
                                                "Hand model · scribbletoad (CC-BY 4.0)"))
                                .font(.caption2).foregroundStyle(Ink.textDim)
                        }.padding(.bottom, 14).padding(.horizontal)
                    }
                }
                .onAppear { handSel = nil }
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
        // Detailed-model drill-down for head / arm / foot (uses the added part GLBs).
        .sheet(item: $detailPart) { cfg in
            PartDetailSheet(config: cfg) { detailPart = nil }
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
                    Button { model.clearSelection() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.textDim)
                    }.accessibilityLabel(AppLocale.pick("关闭", "Close"))
                }
                // Meridian chip — tappable when the channel is one we draw (opens its card).
                Button { if let m = Meridian.by(pt.meridian) { model.selectedPoint = nil; model.selectedMeridian = m } } label: {
                    HStack(spacing: 6) {
                        Text(pt.meridianName).font(.caption).foregroundStyle(Ink.text)
                        if Meridian.by(pt.meridian) != nil {
                            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(Ink.gold)
                        }
                    }
                }.disabled(Meridian.by(pt.meridian) == nil)
                Text(pt.location).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !pt.indications.isEmpty {
                    Text(pt.indications).font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !pt.caution.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Ink.gold)
                        Text(pt.caution).font(.caption2).foregroundStyle(Ink.gold.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if pt.mediapipeTarget != nil {
                    Button(AppLocale.pick("用相机练习", "Practice with camera")) {
                        let p = pt; model.clearSelection(); onPractice(p)
                    }.buttonStyle(GoldButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().panel().padding()
        }
        .transition(.move(edge: .bottom))
    }

    // Tapped-channel card (bottom): meridian name + traditional description + its atlas points as
    // tappable chips. Selecting a chip swaps to that point's detail; the point name tags also float
    // on the body markers (see model.pointLabels / tick()).
    private func meridianPanel(_ m: Meridian) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(m.color).frame(width: 10, height: 10)
                    Text(m.name).font(Typo.serif(18, weight: .semibold)).foregroundStyle(Ink.gold)
                    Text(m.ab).font(Typo.code(15)).foregroundStyle(Ink.textDim)
                    Spacer()
                    Button { model.clearSelection() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.textDim)
                    }.accessibilityLabel(AppLocale.pick("关闭", "Close"))
                }
                Text(m.desc).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                let pts = m.points
                if pts.isEmpty {
                    Text(AppLocale.pick("本图谱暂未收录此经的穴位。",
                                        "No points from this channel are in this atlas yet."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                } else {
                    Text(AppLocale.pick("此经穴位（点按查看）", "Points on this channel (tap for detail)"))
                        .font(.caption2).foregroundStyle(Ink.gold).textCase(.uppercase)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pts) { p in
                                Button { model.selectedPoint = p } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(MeridianColors.color(p.meridian)).frame(width: 7, height: 7)
                                        Text("\(p.id) · \(AppLocale.pick(p.zh, p.en))").font(.caption)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Ink.paperLight).overlay(Capsule().stroke(Ink.line, lineWidth: 1)))
                                    .foregroundStyle(Ink.text)
                                }
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().panel().padding()
        }
        .transition(.move(edge: .bottom))
    }

    // A small floating acupoint name tag drawn over its 3D marker while a meridian is selected.
    private func pointTag(_ lab: AtlasModel.PLabel) -> some View {
        HStack(spacing: 4) {
            Circle().fill(lab.color).frame(width: 6, height: 6)
            Text(lab.text).font(.caption2.bold())
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Ink.paperLight.opacity(0.92))
            .overlay(Capsule().stroke(lab.color.opacity(0.7), lineWidth: 1)))
        .foregroundStyle(Ink.text)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .fixedSize()
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
                    Text(AppLocale.pick("点按发光穴位查看详情。", "Tap a glowing point for its details."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .multilineTextAlignment(.center).padding(.horizontal)
                        .padding(.bottom, PartDetail.forRegion(f.id) == nil ? 26 : 4)
                    if let cfg = PartDetail.forRegion(f.id) {
                        Button(AppLocale.pick("细看模型", "Detailed view")) { detailPart = cfg }
                            .buttonStyle(GoldButtonStyle()).padding(.bottom, 16)
                    }
                }
            } else {
                Text(AppLocale.pick("点按区域放大 · 点按经络或穴位 · 拖动旋转",
                                    "Tap a region to zoom · tap a channel or point · drag to rotate"))
                    .font(.caption).foregroundStyle(Ink.text.opacity(0.7)).multilineTextAlignment(.center)
                    .padding(.horizontal).padding(.bottom, 24)
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
        private var acuNodes: [String: SCNNode] = [:]    // id → marker node, for projecting name tags
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
            // Cache the acupoint marker nodes so a selected meridian can float name tags on them.
            acuNodes.removeAll()
            mesh.enumerateHierarchy { n, _ in
                if let nm = n.name, nm.hasPrefix("acu:") { self.acuNodes[String(nm.dropFirst(4))] = n }
            }
            // Orbit pinch/drag around the body center (origin) in full-body mode, so manual zoom
            // keeps the figure framed instead of dollying toward the scene origin and sliding off.
            view?.defaultCameraController.target = SCNVector3Zero
        }

        // Project each region anchor to a screen point each frame so the brush labels track the
        // rotating body. Body regions hide on the far side; the hand hotspot stays reachable.
        @objc private func tick() {
            guard let view = view else { return }
            // Throttle the @Published republish to ~30 Hz so the overlay isn't diffed at the full
            // 60–120 Hz display rate the whole time the auto-rotating atlas is on screen.
            let now = link?.timestamp ?? 0
            if now - lastPublish < 1.0 / 30.0 { return }
            lastPublish = now

            // Region brush labels: full-body mode only.
            if model.focused == nil && !anchors.isEmpty {
                var out: [AtlasModel.Label] = []
                for (r, node) in anchors {
                    let wp = node.presentation.worldPosition
                    let p = view.projectPoint(wp)
                    guard p.z > 0 && p.z < 1 else { continue }   // off-screen / behind camera
                    // Fade by facing instead of a hard cut, so labels don't pop as the body rotates.
                    let z = Float(wp.z)
                    let opacity = r.isHand ? 1.0 : Double(max(0, min(1, (z + 0.05) / 0.09)))
                    if opacity > 0.02 {
                        out.append(.init(id: r.id, region: r,
                                         point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), opacity: opacity))
                    }
                }
                model.labels = out
            } else if !model.labels.isEmpty {
                model.labels = []
            }

            // Acupoint name tags for the selected meridian (any mode), projected onto their markers.
            if let mer = model.selectedMeridian {
                var out: [AtlasModel.PLabel] = []
                for pt in mer.points {
                    guard let node = acuNodes[pt.id] else { continue }
                    let wp = node.presentation.worldPosition
                    let p = view.projectPoint(wp)
                    guard p.z > 0 && p.z < 1 else { continue }
                    let z = Float(wp.z)
                    let opacity = Double(max(0, min(1, (z + 0.05) / 0.09)))
                    if opacity > 0.04 {
                        out.append(.init(id: pt.id, text: "\(pt.id) · \(AppLocale.pick(pt.zh, pt.en))",
                                         color: MeridianColors.color(pt.meridian),
                                         point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), opacity: opacity))
                    }
                }
                model.pointLabels = out
            } else if !model.pointLabels.isEmpty {
                model.pointLabels = []
            }
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

        // Hit-test a tap against the acupoint markers ("acu:<id>") and the meridian channels
        // ("mer:<id>"). Both draw on top (depth-test off), so a far-side hit can sit under the tap —
        // only accept camera-facing hits. Markers win over channels (you're tapping the point); a
        // channel hit is remembered and selected only if no facing marker was tapped.
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            var meridianHit: String? = nil
            for h in hits {
                let facing = Float(h.worldCoordinates.z) > -0.05
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name {
                        if name.hasPrefix("acu:"), facing {
                            let id = String(name.dropFirst(4))
                            if let pt = Acupoint.all.first(where: { $0.id == id }) {
                                model.selectedMeridian = nil
                                model.pointLabels = []
                                model.selectedPoint = pt
                            }
                            return
                        }
                        if name.hasPrefix("mer:"), facing, meridianHit == nil {
                            meridianHit = String(name.dropFirst(4))
                        }
                    }
                    n = node.parent
                }
            }
            if let mid = meridianHit, let m = Meridian.by(mid) {
                model.selectedPoint = nil
                model.selectedMeridian = m
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
