import SwiftUI
import SceneKit
import GLTFKit2
import simd

// Reusable detailed drill-down for a single body-part model (head / arm / foot), mirroring the
// hand chart: load a posed GLB, centre + scale to a unit box, orient it to a canonical view, and
// raycast each region acupoint onto the surface as a tappable marker. Shared marker/material/mesh/
// tap helpers live in SceneKitAtlas.
//
// These assets are arbitrarily posed (Maya/FBX frames), so placement is a tunable layout, not a
// derived anatomy. `PartDetail.euler` orients the model and `layout` gives each point a normalized
// (u,v) in the camera plane ([-0.5…0.5], u→right, v→up); the marker is raycast onto the surface so
// it sits ON the mesh regardless of the model's local axes. Points in `back` are raycast from the
// FAR side (e.g. KI1 on the sole), so they land on the back surface and reveal on rotation. If a
// part reads rotated/mirrored on device, tweak its `euler` / `layout` here (a one-time visual nudge).

struct PartDetail: Identifiable {
    let id: String                              // region id (head/arm/foot) — also the title key
    let resource: String                        // GLB file name (no extension)
    let euler: SCNVector3                        // orientation to a sensible canonical view
    let layout: [String: SIMD2<Float>]           // acupoint id → (u, v) in the camera plane
    let back: Set<String>                        // points on the far/under surface (raycast reversed)
    let titleZh: String; let titleEn: String
    let creditZh: String; let creditEn: String

    var points: [Acupoint] { Acupoint.all.filter { $0.region == id && layout[$0.id] != nil } }

    static func forRegion(_ region: String) -> PartDetail? { byRegion[region] }
    static let byRegion: [String: PartDetail] = [
        "head": PartDetail(
            id: "head", resource: "low_poly_head", euler: SCNVector3(0, 0, 0),
            layout: ["EX-HN3": [0.00, 0.10], "EX-HN5": [0.22, 0.06], "GV20": [0.00, 0.44], "EX-HN1": [0.00, 0.34]],
            back: [],
            titleZh: "头", titleEn: "Head",
            creditZh: "头部模型 · 低多边形（参考用）", creditEn: "Head model · low-poly (reference)"),
        "arm": PartDetail(
            id: "arm", resource: "lowpoly_arm", euler: SCNVector3(-Float.pi / 2, 0.3, 0),
            layout: ["LI11": [0.12, 0.40], "LU5": [-0.06, 0.40], "TE4": [0.05, -0.36], "PC7": [0.00, -0.42]],
            back: [],
            titleZh: "手臂", titleEn: "Arm",
            creditZh: "手臂模型 · 低多边形（参考用）", creditEn: "Arm model · low-poly (reference)"),
        "foot": PartDetail(
            id: "foot", resource: "foot_low_poly", euler: SCNVector3(0, Float.pi / 2, 0),
            layout: ["LR3": [0.12, 0.12], "ST44": [0.22, 0.08], "KI1": [0.10, -0.20], "KI3": [-0.26, 0.00]],
            back: ["KI1"],                       // Yongquan is on the sole — raycast onto the under-surface
            titleZh: "足部", titleEn: "Foot",
            creditZh: "足部模型 · 低多边形（参考用）", creditEn: "Foot model · low-poly (reference)"),
    ]
}

struct PartModel3DView: UIViewRepresentable {
    let config: PartDetail
    var onSelect: (Acupoint) -> Void = { _ in }

    func makeCoordinator() -> AcuTapCoordinator { AcuTapCoordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        AtlasMarkers.addStudioLighting(to: scene)
        view.scene = scene
        context.coordinator.view = view

        let cfg = config
        if let url = Bundle.main.url(forResource: cfg.resource, withExtension: "glb") {
            GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
                guard status == .complete, let asset = maybeAsset else { return }
                let gltf = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    guard let mesh = AtlasMarkers.unitMesh(from: gltf, material: AtlasMarkers.meshMaterial()) else { return }
                    mesh.eulerAngles = cfg.euler
                    scene.rootNode.addChildNode(mesh)

                    placeMarkers(in: scene, mesh: mesh, config: cfg)
                    AtlasMarkers.installCamera(z: 2.4, in: scene, for: view)
                }
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AcuTapCoordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // World AABB of the transformed mesh (so the (u,v) layout auto-fits any model's size), then
    // raycast each layout point along ±Z onto the camera-facing surface (or the far side for `back`
    // points like a sole point).
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
        for pt in config.points {
            guard let uv = config.layout[pt.id] else { continue }
            let X = cx + uv.x * w, Y = cy + uv.y * h
            let fromBack = config.back.contains(pt.id)
            // Front points: ray originates beyond +Z and the closest hit is the camera-facing
            // surface. Back points (e.g. a sole point): ray originates beyond −Z so the closest hit
            // is the far/under surface. (Both span the full mesh depth + margin so neither is missed.)
            let from = SCNVector3(X, Y, fromBack ? wlo.z - 0.6 : whi.z + 0.6)
            let to   = SCNVector3(X, Y, fromBack ? whi.z + 0.6 : wlo.z - 0.6)
            let hits = scene.rootNode.hitTestWithSegment(from: from, to: to, options: [
                SCNHitTestOption.backFaceCulling.rawValue: false,
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            ])
            guard let hit = hits.first else { continue }
            let p = hit.worldCoordinates
            let dz: Float = fromBack ? -0.02 : 0.02       // sit just proud of the hit surface
            // Draw on top (depth-off) so every marker is visible; back/sole points are placed on the
            // far surface anatomically and read as projected dots from the front.
            scene.rootNode.addChildNode(AtlasMarkers.node(
                id: pt.id, color: UIColor(MeridianColors.color(pt.meridian)),
                coreRadius: 0.024, haloRadius: 0.044, at: SCNVector3(p.x, p.y, p.z + dz)))
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
                            Text(AppLocale.pick("点按发光穴位查看详情：" + config.points.map { "\($0.id) \($0.zh)" }.joined(separator: " · "),
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
