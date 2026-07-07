import SwiftUI
import SceneKit
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
    let nodeName: String?                        // geometry node to extract from a multi-part GLB (else first)
    let euler: SCNVector3                        // orientation to a sensible canonical view
    let layout: [String: SIMD2<Float>]           // acupoint id → (u, v) in the camera plane
    let back: Set<String>                        // points on the far/under surface (raycast reversed)
    let titleZh: String; let titleEn: String
    let creditZh: String; let creditEn: String

    var points: [Acupoint] { Acupoint.all.filter { $0.region == id && layout[$0.id] != nil } }

    static func forRegion(_ region: String) -> PartDetail? { byRegion[region] }
    static let byRegion: [String: PartDetail] = [
        // Head/arm/foot all come from the composite body model — its parts (real face, full arm with
        // hand, proper foot) are far better formed than the standalone single-part GLBs they replaced.
        "head": PartDetail(
            // Frontal at identity: real eyes/nose/ears, so the face points read anatomically.
            id: "head", resource: "arms_hands_head_legs_and_feet__low_poly_female",
            nodeName: "polySurface1_lambert1_0", euler: SCNVector3(0, 0, 0),
            // GV20 sits ON the vertex (0.48 floated the dome above the crown); EX-HN1 is its
            // just-anterior companion on the top of the dome, not the forehead slope; EX-HN5 lands
            // in the temple hollow, a touch more lateral. Tuned via detail_head.png.
            layout: ["EX-HN3": [0.00, 0.05], "EX-HN5": [0.36, 0.05], "GV20": [0.00, 0.455], "EX-HN1": [0.00, 0.415]],
            back: [],
            titleZh: "头", titleEn: "Head",
            creditZh: "头部模型 · pnhtuan（CC-BY 4.0）", creditEn: "Head model · pnhtuan (CC-BY 4.0)"),
        "arm": PartDetail(
            // Full arm (shoulder → hand), horizontal with the dorsum to the camera (matches the foot's
            // chart style). Palmar points (LU5 cubital crease / PC7 wrist crease) raycast to the FAR
            // surface — like KI1 on the sole, they reveal on rotation.
            id: "arm", resource: "arms_hands_head_legs_and_feet__low_poly_female",
            nodeName: "polySurface6_lambert1_0", euler: SCNVector3(0, 0.5, -0.8),
            // LI11/LU5 belong AT the elbow crease (0.20 drifted onto the upper arm). Tuned via
            // detail_arm.png.
            layout: ["LI11": [0.16, 0.04], "LU5": [0.13, 0.00], "TE4": [-0.23, 0.03], "PC7": [-0.25, -0.05]],
            back: ["LU5", "PC7"],
            titleZh: "手臂", titleEn: "Arm",
            creditZh: "手臂模型 · pnhtuan（CC-BY 4.0）", creditEn: "Arm model · pnhtuan (CC-BY 4.0)"),
        // Proper foot from the composite body model (polySurface9) — the standalone foot_low_poly asset
        // was a malformed, stubby lump. 3/4 lateral view (toes right, dorsum to camera).
        "foot": PartDetail(
            id: "foot", resource: "arms_hands_head_legs_and_feet__low_poly_female",
            nodeName: "polySurface9_lambert1_0", euler: SCNVector3(-0.4, Float.pi / 2, 0),
            // LR3 sits distal on the dorsum (toward the 1st/2nd web), ST44 right at the toe
            // webbing — both were a touch proximal. Tuned via detail_foot.png.
            layout: ["LR3": [0.10, -0.11], "ST44": [0.29, -0.13], "KI1": [0.14, -0.22], "KI3": [-0.22, -0.10]],
            back: ["KI1"],                       // Yongquan is on the sole — raycast onto the under-surface
            titleZh: "足部", titleEn: "Foot",
            creditZh: "足部模型 · pnhtuan（CC-BY 4.0）", creditEn: "Foot model · pnhtuan (CC-BY 4.0)"),
    ]
}

struct PartModel3DView: UIViewRepresentable {
    let config: PartDetail
    var resetToken: Int = 0                      // bump to animate the camera back to canonical
    var loading: Binding<Bool>? = nil            // reports GLB decode state to the sheet chrome
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
        // A re-presented sheet can carry a non-zero token from its parent into a FRESH coordinator
        // (lastResetToken 0); sync here so the first updateUIView doesn't fire a spurious reset.
        context.coordinator.lastResetToken = resetToken

        // Shared cache/decode/camera scaffolding (SceneKitAtlas.installDetailMesh); this view only
        // supplies the part's canonical pose + its marker placement.
        let cfg = config
        AtlasMarkers.installDetailMesh(resource: cfg.resource, nodeName: cfg.nodeName,
                                       euler: cfg.euler, cameraZ: 2.4,
                                       in: scene, view: view, coordinator: context.coordinator,
                                       loading: loading) { mesh in
            placeMarkers(in: scene, mesh: mesh, config: cfg)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(AcuTapCoordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // The sheet's "reset view" button bumps resetToken → animate the camera home.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetCamera()
        }
    }

    // Geometry-based marker placement: cast a ray from the camera through each acupoint's (u,v) fraction
    // of the model (AtlasMarkers.screenMarker) so dots land on the VISIBLE surface regardless of pose —
    // replaces the old world-Z raycast that drifted off / missed on these arbitrarily-posed GLBs. Pure
    // geometry, so no dependence on view layout/render timing.
    private func placeMarkers(in scene: SCNScene, mesh: SCNNode, config: PartDetail) {
        for pt in config.points {
            guard let uv = config.layout[pt.id] else { continue }
            if let m = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: mesh, u: uv.x, v: uv.y, farSide: config.back.contains(pt.id),
                                                 id: pt.id, color: UIColor(MeridianColors.color(pt.meridian)),
                                                 core: 0.03, halo: 0.055) {
                scene.rootNode.addChildNode(m)
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
    @State private var loading = false           // set by PartModel3DView while its GLB decodes
    @State private var resetToken = 0            // bumped by the "reset view" toolbar button

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                PartModel3DView(config: config, resetToken: resetToken, loading: $loading,
                                onSelect: { sel = $0 }).ignoresSafeArea()
                if loading { AtlasLoadingIndicator() }
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let s = sel {
                            HStack(spacing: 8) {
                                Circle().fill(MeridianColors.color(s.meridian)).frame(width: 9, height: 9)
                                Text("\(s.id) · \(s.zh)").font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                                Text(s.en).font(Typo.code(15)).foregroundStyle(Ink.textDim)
                            }
                            if !s.role.isEmpty {
                                Text(s.role).font(.caption2).foregroundStyle(Ink.gold.opacity(0.85))
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(s.location).font(.caption).foregroundStyle(Ink.text)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            if !s.indications.isEmpty {
                                Text(s.indications).font(.caption2).foregroundStyle(Ink.textDim)
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { resetToken += 1 } label: { Image(systemName: "arrow.counterclockwise") }
                        .tint(Ink.gold)
                        .accessibilityLabel(AppLocale.pick("重置视角", "Reset view"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("完成", "Done")) { onClose() }.tint(Ink.gold)
                }
            }
        }
    }
}
