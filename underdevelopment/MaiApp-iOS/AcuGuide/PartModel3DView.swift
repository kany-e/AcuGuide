import SwiftUI
import SceneKit
import GLTFKit2
import simd

// Reusable detailed drill-down for a single body-part model (head / arm / foot), mirroring the
// hand chart: load a posed GLB, centre + scale to a unit box, orient it to a canonical view, and
// raycast each region acupoint onto the camera-facing surface as a tappable marker.
//
// These assets are arbitrarily posed (Maya/FBX frames), so — like the hand chart — placement is a
// tunable layout, not a derived anatomy. `PartDetail.euler` orients the model and `layout` gives
// each point a normalized (u,v) in the camera plane ([-0.5…0.5], u→right, v→up); the marker is then
// raycast onto the surface so it always sits ON the mesh regardless of the model's local axes. If a
// part reads rotated/mirrored on device, tweak its `euler` / `layout` here (a one-time visual nudge,
// the same kind TE3 and the hand chart needed).

struct PartDetail: Identifiable {
    let id: String                              // region id (head/arm/foot) — also the title key
    let resource: String                        // GLB file name (no extension)
    let euler: SCNVector3                        // orientation to a sensible canonical view
    let layout: [String: SIMD2<Float>]           // acupoint id → (u, v) in the camera plane
    let titleZh: String; let titleEn: String
    let creditZh: String; let creditEn: String

    var points: [Acupoint] { Acupoint.all.filter { $0.region == id && layout[$0.id] != nil } }

    static func forRegion(_ region: String) -> PartDetail? { byRegion[region] }
    static let byRegion: [String: PartDetail] = [
        "head": PartDetail(
            id: "head", resource: "low_poly_head", euler: SCNVector3(0, 0, 0),
            layout: ["EX-HN3": [0.00, 0.10], "EX-HN5": [0.22, 0.06], "GV20": [0.00, 0.44], "EX-HN1": [0.00, 0.34]],
            titleZh: "头部", titleEn: "Head",
            creditZh: "头部模型 · 低多边形（参考用）", creditEn: "Head model · low-poly (reference)"),
        "arm": PartDetail(
            id: "arm", resource: "lowpoly_arm", euler: SCNVector3(-Float.pi / 2, 0.3, 0),
            layout: ["LI11": [0.12, 0.40], "LU5": [-0.06, 0.40], "TE4": [0.05, -0.36], "PC7": [0.00, -0.42]],
            titleZh: "手臂", titleEn: "Arm",
            creditZh: "手臂模型 · 低多边形（参考用）", creditEn: "Arm model · low-poly (reference)"),
        "foot": PartDetail(
            id: "foot", resource: "foot_low_poly", euler: SCNVector3(0, Float.pi / 2, 0),
            layout: ["LR3": [0.12, 0.12], "ST44": [0.22, 0.08], "KI1": [0.10, -0.20], "KI3": [-0.26, 0.00]],
            titleZh: "足部", titleEn: "Foot",
            creditZh: "足部模型 · 低多边形（参考用）", creditEn: "Foot model · low-poly (reference)"),
    ]
}

struct PartModel3DView: UIViewRepresentable {
    let config: PartDetail
    var onSelect: (Acupoint) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.intensity = 740; amb.light?.color = UIColor.white
        scene.rootNode.addChildNode(amb)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .directional
        fill.light?.intensity = 240; fill.light?.color = UIColor(Color(hex: "#fffaf0"))
        fill.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 7, 0)
        scene.rootNode.addChildNode(fill)
        view.scene = scene
        context.coordinator.view = view

        let cfg = config
        if let url = Bundle.main.url(forResource: cfg.resource, withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltf = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    var found: SCNGeometry? = nil
                    gltf.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
                    guard let found else { return }
                    let geo = found.copy() as! SCNGeometry
                    geo.materials = [partMaterial()]
                    let mesh = SCNNode(geometry: geo)
                    let (lo, hi) = mesh.boundingBox
                    mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
                    let extent = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
                    let s = extent > 0 ? 1.0 / extent : 1
                    mesh.scale = SCNVector3(s, s, s)
                    mesh.eulerAngles = cfg.euler
                    scene.rootNode.addChildNode(mesh)

                    placeMarkers(in: scene, mesh: mesh, config: cfg)

                    let cam = SCNNode()
                    cam.camera = SCNCamera()
                    cam.camera?.fieldOfView = 45
                    cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
                    cam.position = SCNVector3(0, 0, 2.4)
                    scene.rootNode.addChildNode(cam)
                    view.pointOfView = cam
                    view.defaultCameraController.target = SCNVector3Zero
                }
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // World AABB of the transformed mesh (so the (u,v) layout auto-fits any model's size), then
    // raycast each layout point straight down −Z onto the camera-facing surface.
    private func placeMarkers(in scene: SCNScene, mesh: SCNNode, config: PartDetail) {
        let (lo, hi) = mesh.boundingBox
        var wlo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var whi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for cx in [lo.x, hi.x] { for cy in [lo.y, hi.y] { for cz in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(cx, cy, cz), to: nil)
            wlo = simd_min(wlo, SIMD3(w.x, w.y, w.z)); whi = simd_max(whi, SIMD3(w.x, w.y, w.z))
        } } }
        let cx = (wlo.x + whi.x) / 2, cy = (wlo.y + whi.y) / 2
        let w = (whi.x - wlo.x) * 0.92, h = (whi.y - wlo.y) * 0.92
        let zFar = whi.z + 0.6, zNear = wlo.z - 0.6
        for pt in config.points {
            guard let uv = config.layout[pt.id] else { continue }
            let X = cx + uv.x * w, Y = cy + uv.y * h
            let hits = scene.rootNode.hitTestWithSegment(
                from: SCNVector3(X, Y, zFar), to: SCNVector3(X, Y, zNear), options: [
                    SCNHitTestOption.backFaceCulling.rawValue: false,
                    SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
                ])
            guard let hit = hits.first else { continue }
            let p = hit.worldCoordinates
            scene.rootNode.addChildNode(marker(for: pt, at: SCNVector3(p.x, p.y, p.z + 0.02)))
        }
    }

    private func marker(for pt: Acupoint, at pos: SCNVector3) -> SCNNode {
        let col = UIColor(MeridianColors.color(pt.meridian))
        let core = SCNSphere(radius: 0.024); core.firstMaterial = glowMat(col, 1.0)
        let halo = SCNSphere(radius: 0.044); halo.firstMaterial = glowMat(col, 0.25)
        let node = SCNNode(geometry: core)
        let h = SCNNode(geometry: halo); h.renderingOrder = 14; node.addChildNode(h)
        node.position = pos
        node.name = "acu:" + pt.id
        node.renderingOrder = 15
        return node
    }

    private func glowMat(_ color: UIColor, _ opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = opacity
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        return m
    }

    final class Coordinator: NSObject {
        weak var view: SCNView?
        let onSelect: (Acupoint) -> Void
        init(onSelect: @escaping (Acupoint) -> Void) { self.onSelect = onSelect }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name, name.hasPrefix("acu:") {
                        let id = String(name.dropFirst(4))
                        if let pt = Acupoint.all.first(where: { $0.id == id }) { onSelect(pt); return }
                    }
                    n = node.parent
                }
            }
        }
    }
}

// The drill-down sheet shown over a focused region — the rotatable detailed model + a tapped-point
// detail card, matching the hand chart's chrome.
struct PartDetailSheet: View {
    let config: PartDetail
    var onClose: () -> Void
    @State private var sel: Acupoint? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                PartModel3DView(config: config, onSelect: { sel = $0 }).ignoresSafeArea()
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let s = sel {
                            HStack(spacing: 8) {
                                Circle().fill(MeridianColors.color(s.meridian)).frame(width: 9, height: 9)
                                Text("\(s.id) · \(s.zh)").font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                                Text(s.en).font(Typo.code(15)).foregroundStyle(Ink.textDim)
                            }
                            Text(s.location).font(.caption).foregroundStyle(Ink.text)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            if !s.caution.isEmpty {
                                Text(s.caution).font(.caption2).foregroundStyle(Ink.gold.opacity(0.9))
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            let names = config.points.map { "\($0.id) \($0.zh)" }.joined(separator: " · ")
                            Text(AppLocale.pick("点按发光穴位查看详情：\(names)",
                                                "Tap a glowing point for its details: " + config.points.map { "\($0.id) \($0.en)" }.joined(separator: " · ")))
                                .font(.caption).foregroundStyle(Ink.text.opacity(0.78))
                                .multilineTextAlignment(.center)
                        }
                        Text(AppLocale.pick(config.creditZh, config.creditEn))
                            .font(.caption2).foregroundStyle(Ink.textDim)
                    }.padding(.bottom, 14).padding(.horizontal)
                }
            }
            .navigationTitle(AppLocale.pick(config.titleZh, config.titleEn))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { onClose() }.tint(Ink.gold)
            } }
        }
    }
}

private func partMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.metalness.contents = 0.0
    m.roughness.contents = 1.0
    m.diffuse.contents = UIColor(Color(hex: "#bcae93"))   // warm parchment-sage, matches the hand
    m.emission.contents = UIColor(Color(hex: "#2c3626")); m.emission.intensity = 0.10
    m.isDoubleSided = true
    return m
}
