import SwiftUI
import SceneKit
import GLTFKit2
import simd

// Rotatable 3D body — native port of the archived web atlas's Body3D.jsx. Loads the SAME asset as the web app,
// model.glb, at runtime via GLTFKit2 (no usdz / no drift). Sage-green matte material, soft
// lighting, gentle auto-rotate, meridian channels along the skeleton, and brush-style region
// labels (头/胸/腹/臂/腿/足/手部) projected onto the body. Tapping a body region zooms the camera
// in to that part (a 全身/Full-body control returns); tapping 手部 drills into the hand acupoint
// map (mirrors the web onEnterHand). The capsule shows only if the model is missing.

// Shared state between the SwiftUI overlay and the SceneKit coordinator.
final class AtlasModel: ObservableObject {
    // Both label structs are Equatable so the 30 Hz projector can skip the @Published republish
    // (and the SwiftUI invalidation it causes) whenever nothing on screen actually moved.
    struct Label: Identifiable, Equatable { let id: String; let region: BodyAtlas.Region; let point: CGPoint; let opacity: Double }
    // A floating acupoint name tag drawn at a projected marker position (while a meridian is
    // selected, or while a region is focused — its revealed markers get the same tags). `dx`
    // hangs the tag to the marker's LEFT or RIGHT (alternating, stable per point) so a cluster of
    // points doesn't stack every label on one side (user-reported crowding).
    struct PLabel: Identifiable, Equatable {
        let id: String; let text: String; let color: Color
        let point: CGPoint; let opacity: Double; let dx: CGFloat
    }
    @Published var labels: [Label] = []          // region labels projected to screen (full-body mode)
    @Published var pointLabels: [PLabel] = []    // acupoint name tags (selected meridian / focused region)
    @Published var focused: BodyAtlas.Region?    // non-nil while zoomed into a region
    @Published var selectedPoint: Acupoint?      // a tapped 3D acupoint marker
    @Published var selectedMeridian: Meridian?   // a tapped channel → its card + point tags
    @Published var meshLoading = true            // model.glb decode in flight → spinner in the chrome
    // True only while the atlas is actually on screen (Body3DView .onAppear/.onDisappear — they
    // fire on tab switches and under full-screen covers). Gates the coordinator's CADisplayLink so
    // the projector doesn't tick at display rate for the app's lifetime after the first atlas
    // visit (TabView keeps the view alive). Not @Published — no view renders from it.
    var atlasVisible = true { didSet { coordinator?.syncDisplayLinkPaused() } }
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
    @State private var showLegend = false            // marker legend (auto-shown once; "?" reopens)
    @State private var showHandChart = false        // 3D finger-detail hand for the hand region
    @State private var handChartCoach: Acupoint? = nil
    @State private var handSel: Acupoint? = nil      // a tapped marker on the detailed hand chart
    @State private var handResetToken = 0            // hand sheet "reset view" trigger
    @State private var handLoading = false           // hand GLB decode in flight
    @State private var detailPart: PartDetail? = nil // head/arm/foot detailed-model drill-down
    @State private var locate: Acupoint? = nil       // front-camera region locator (face / torso)
    @State private var sourcesFor: Acupoint? = nil   // "Research & sources" sheet from a point card

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
                    pointTag(lab)
                        .position(x: lab.point.x + lab.dx, y: lab.point.y)
                        .opacity(lab.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Full-body model.glb decode in flight → centered spinner (the capsule placeholder
            // renders beneath it until the figure swaps in).
            if model.meshLoading { AtlasLoadingIndicator() }

            chrome

            if let pt = model.selectedPoint { pointPanel(pt) }
            else if let m = model.selectedMeridian { meridianPanel(m) }

            if showLegend { legendPanel }
        }
        .onAppear {
            model.atlasVisible = true            // resume the projector display link
            // The marker legend auto-shows on the first atlas visit; "seen" is stamped on dismissal
            // (not on show), so an ignored panel re-appears next time. "?" re-opens it anytime.
            if !UserDefaults.standard.bool(forKey: "atlasLegendSeen") { showLegend = true }
        }
        // Fires on tab switches AND under full-screen covers → pause the display link so the 30 Hz
        // projector isn't burning frames while the atlas can't be seen.
        .onDisappear { model.atlasVisible = false }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showHandChart, onDismiss: {
            // pending + onDismiss pattern: the practice button STASHES the point and dismisses;
            // the coach cover is launched only here, after the sheet is fully gone. Dismissing the
            // sheet and presenting the cover in the SAME update can silently drop the cover on
            // iOS 16.0–16.3.
            if let pt = handChartCoach { handChartCoach = nil; onPractice(pt) }
        }) {
            // Detailed 3D hand (real fingers) for the hand drill-down — the body's hand is a mitten.
            NavigationStack {
                ZStack {
                    ShanshuiBackground()
                    HandModel3DView(resetToken: handResetToken, loading: $handLoading,
                                    onSelect: { handSel = $0 }).ignoresSafeArea()
                    if handLoading { AtlasLoadingIndicator() }
                    VStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if let s = handSel {
                                // Tapped-marker detail — the shared rich card (meridian, role,
                                // location, uses, caution), not just the location line.
                                AtlasPointCard(pt: s)
                                Button(s.mediapipeTarget != nil
                                       ? AppLocale.pick("用相机练习", "Practice with camera")
                                       : AppLocale.pick("计时引导练习", "Guided practice (timer)")) { handChartCoach = s }
                                        .buttonStyle(GoldButtonStyle())
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { handResetToken += 1 } label: { Image(systemName: "arrow.counterclockwise") }
                            .tint(Ink.gold)
                            .accessibilityLabel(AppLocale.pick("重置视角", "Reset view"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocale.pick("完成", "Done")) { showHandChart = false }.tint(Ink.gold)
                    }
                }
            }
            .onChange(of: handChartCoach) { v in
                if v != nil { showHandChart = false }   // stash → dismiss; onDismiss launches practice
            }
        }
        // Detailed-model drill-down for head / arm / foot (uses the added part GLBs).
        .sheet(item: $detailPart) { cfg in
            PartDetailSheet(config: cfg) { detailPart = nil }
        }
        // Front-camera locator: mark the point on the user's own face (head points) or body (torso).
        .fullScreenCover(item: $locate) { pt in
            if FaceAcupoints.isLocatable(pt.id) { FaceAtlasView(focus: pt) { locate = nil } }
            else { TorsoAtlasView(focus: pt) { locate = nil } }
        }
        // Research & sources for the tapped point (honest AcuTrials evidence + citations).
        .sheet(item: $sourcesFor) { pt in
            NavigationStack {
                SourcesView(focusPointId: pt.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocale.pick("完成", "Done")) { sourcesFor = nil }.tint(Ink.gold)
                    } }
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
                    Button { model.clearSelection() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.textDim)
                    }.accessibilityLabel(AppLocale.pick("关闭", "Close"))
                }
                // Standard English name (e.g. "Inner Pass") under the header.
                if !pt.englishName.isEmpty {
                    Text(pt.englishName).font(Typo.serif(14)).italic().foregroundStyle(Ink.textDim)
                }
                // Meridian chip — tappable when the channel is one we draw (opens its card).
                Button { if let m = Meridian.by(pt.meridian) { model.selectedPoint = nil; model.pointLabels = []; model.selectedMeridian = m } } label: {
                    HStack(spacing: 6) {
                        Text(pt.meridianName).font(.caption).foregroundStyle(Ink.text)
                        if Meridian.by(pt.meridian) != nil {
                            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(Ink.gold)
                        }
                    }
                }.disabled(Meridian.by(pt.meridian) == nil)
                // Classical role (Five-Shu / Yuan / Luo / Front-Mu …) — traditional framing only.
                if !pt.role.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "seal").font(.caption2).foregroundStyle(Ink.gold)
                        Text(pt.role).font(.caption).foregroundStyle(Ink.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(pt.location).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !pt.indications.isEmpty {
                    Text(pt.indications).font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Honest research-evidence affordance → the Sources & Evidence screen.
                if Evidence.forPoint(pt.id) != nil {
                    Button { sourcesFor = pt } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "text.book.closed").font(.caption2)
                            Text(AppLocale.pick("研究与来源", "Research & sources")).font(.caption.weight(.medium))
                            Image(systemName: "chevron.right").font(.caption2.bold())
                        }.foregroundStyle(Ink.gold)
                    }.padding(.top, 1)
                }
                if !pt.caution.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Ink.gold)
                        Text(pt.caution).font(.caption2).foregroundStyle(Ink.gold.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(pt.mediapipeTarget != nil
                       ? AppLocale.pick("用相机练习", "Practice with camera")
                       : AppLocale.pick("计时引导练习", "Guided practice (timer)")) {
                        let p = pt; model.clearSelection(); onPractice(p)
                    }.buttonStyle(GoldButtonStyle())
                if FaceAcupoints.isLocatable(pt.id) {
                    Button(AppLocale.pick("在我的脸上定位", "Find on my face")) {
                        let p = pt; model.clearSelection(); locate = p
                    }.buttonStyle(GoldButtonStyle())
                }
                if TorsoAcupoints.isLocatable(pt.id) {
                    Button(AppLocale.pick("在我身上定位", "Find on my body")) {
                        let p = pt; model.clearSelection(); locate = p
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
                                // Clear the meridian + its floating tags, matching the marker tap
                                // path — otherwise stale name tags render behind the point card.
                                Button { model.selectedMeridian = nil; model.pointLabels = []; model.selectedPoint = p } label: {
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

    // Dismissable marker legend: what the glowing dots, the colored channel lines, and the brush
    // region names each do. Auto-shown on the first visit (see .onAppear / "atlasLegendSeen");
    // afterwards the "?" chrome button re-opens it.
    private var legendPanel: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppLocale.pick("图例", "Legend"))
                        .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                    Spacer()
                    Button { dismissLegend() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.textDim)
                    }.accessibilityLabel(AppLocale.pick("关闭图例", "Close legend"))
                }
                // Ink swatches match the shanshui restyle (was a gold glowing dot + jade "colored
                // line" — the atlas has neither anymore; review-caught legend drift).
                legendRow(Circle().fill(BodyAtlas.inkSwatch).frame(width: 10, height: 10),
                          "墨点：穴位，点按查看详情。",
                          "Ink dot: an acupoint — tap it for details.")
                legendRow(Capsule().fill(BodyAtlas.inkSwatch).frame(width: 22, height: 2.5),
                          "墨线：经络，点按后会以经络本色亮起并显示穴位。",
                          "Ink stroke: a meridian channel — tap it to light it in its color and show its points.")
                legendRow(Text("手").font(Typo.brush(16)).foregroundStyle(Ink.brush),
                          "毛笔区域名：点按放大到该部位。",
                          "Brush region name: tap it to zoom in.")
                Button(AppLocale.pick("知道了", "Got it")) { dismissLegend() }
                    .buttonStyle(GoldButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .panel()
            .frame(maxWidth: 340)
            .padding(.horizontal)
            .padding(.top, 64)   // clears the top chrome bar (back / ? / gear)
            Spacer()
        }
        .transition(.opacity)
    }

    private func legendRow(_ swatch: some View, _ zh: String, _ en: String) -> some View {
        HStack(spacing: 10) {
            swatch.frame(width: 24)
            Text(AppLocale.pick(zh, en))
                .font(.caption).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func dismissLegend() {
        UserDefaults.standard.set(true, forKey: "atlasLegendSeen")
        withAnimation(.easeOut(duration: 0.2)) { showLegend = false }
    }

    // Safe-area-respecting controls: a top bar (back when zoomed, ? + gear always) + a bottom hint.
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
                Button { withAnimation(.easeOut(duration: 0.2)) { showLegend = true } } label: {
                    Image(systemName: "questionmark")
                        .font(.callout).foregroundStyle(Ink.text)
                        .padding(9)
                        .background(Circle().fill(Ink.paperLight).overlay(Circle().stroke(Ink.line, lineWidth: 1)))
                }
                .accessibilityLabel(AppLocale.pick("图例", "Legend"))
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
                    Text(AppLocale.pick("点按穴位查看详情。", "Tap a point for its details."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .multilineTextAlignment(.center).padding(.horizontal)
                        .padding(.bottom, PartDetail.forRegion(f.id) == nil ? 26 : 4)
                    if let cfg = PartDetail.forRegion(f.id) {
                        Button(AppLocale.pick("细看模型", "Detailed view")) { detailPart = cfg }
                            .buttonStyle(GoldButtonStyle()).padding(.bottom, 16)
                    }
                }
            } else {
                Text(AppLocale.pick("点按区域放大 · 点按经络查看穴位 · 拖动旋转",
                                    "Tap a region to zoom · tap a channel for its points · drag to rotate"))
                    .font(.caption).foregroundStyle(Ink.text.opacity(0.7)).multilineTextAlignment(.center)
                    .padding(.horizontal).padding(.bottom, 24)
                    .allowsHitTesting(false)   // don't block the (bottom-positioned) 足/Foot label
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
        let spin = SCNNode()                                   // orientation container (no auto-spin;
        scene.rootNode.addChildNode(spin)                      // the user drags to rotate the camera)

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
                guard status == .complete, let asset = maybeAsset else {
                    // Intermediate statuses just report progress; only .error is terminal.
                    if status == .error { DispatchQueue.main.async { model.meshLoading = false } }
                    return
                }
                let gltfScene = SCNScene(gltfAsset: asset)
                DispatchQueue.main.async {
                    // GLTFKit2's skinner collapses the rigged mesh to a point; render the static
                    // bind-pose geometry directly. Authored Z-up (lying down) → -90°X stands it up.
                    var found: SCNGeometry? = nil
                    gltfScene.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
                    guard let found else { model.meshLoading = false; return }
                    capsule.removeFromParentNode()
                    let geometry = found.copy() as! SCNGeometry
                    geometry.materials = [sageMaterial()]
                    let mesh = SCNNode(geometry: geometry)
                    let (lo, hi) = mesh.boundingBox
                    mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
                    mesh.addChildNode(BodyAtlas.channels(on: mesh))  // meridian channels (skeleton-routed, surface-projected)
                    mesh.addChildNode(BodyAtlas.markers(on: mesh))  // 3D acupoint markers, surface-snapped
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
                    model.meshLoading = false
                }
            }
        } else {
            // No bundled model → the capsule placeholder IS the scene; don't spin forever.
            // (Async so the @Published write never lands inside the update that ran makeUIView.)
            DispatchQueue.main.async { model.meshLoading = false }
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
        private var channelNodes: [String: [SCNNode]] = [:]   // meridian id → its channel node(s) (both sides)
        private var highlightedMer: String? = nil        // the channel currently lit in its meridian hue
        private var labeledKey: String? = nil            // cached tag source ("mer:<id>" / "reg:<id>")…
        private var labeledNodes: [(pt: Acupoint, node: SCNNode)] = []   // …and its points + marker nodes
        private var link: CADisplayLink?
        private var lastPublish: CFTimeInterval = 0
        // Where the camera orbits (origin in full-body mode, the region centre when focused) —
        // the reference point for the point-label facing fade below.
        private var orbitCenter = simd_float3(repeating: 0)

        init(model: AtlasModel) { self.model = model; super.init() }

        func attach(view: SpinSCNView, spin: SCNNode) {
            self.view = view; self.spin = spin
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            l.isPaused = !model.atlasVisible
            link = l
        }

        // The projector display link runs ONLY while the atlas is on screen; Body3DView drives
        // model.atlasVisible from .onAppear/.onDisappear (tab switches, full-screen covers).
        func syncDisplayLinkPaused() { link?.isPaused = !model.atlasVisible }

        func installBody(cam: SCNNode, radius: Float, anchorsOn mesh: SCNNode) {
            self.cam = cam; self.radius = radius
            self.mesh = mesh
            anchors = BodyAtlas.regions.map { r in
                let n = SCNNode(); n.simdPosition = r.anchor; mesh.addChildNode(n)
                return (r, n)
            }
            // Cache the acupoint marker nodes so a selected meridian can float name tags on them,
            // and the channel nodes (both sides, keyed by meridian id) so a tapped channel can be
            // lit in its meridian hue.
            acuNodes.removeAll(); channelNodes.removeAll(); highlightedMer = nil
            mesh.enumerateHierarchy { n, _ in
                guard let nm = n.name else { return }
                if nm.hasPrefix("acu:") { self.acuNodes[String(nm.dropFirst(4))] = n }
                else if nm.hasPrefix("mer:") { self.channelNodes[String(nm.dropFirst(4)), default: []].append(n) }
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

            // Light the SELECTED channel in its meridian hue (both sides), reset the previous one —
            // the resting ink is near-identical across channels, so this is the tapped channel's
            // only on-body identity. Guarded, so it's a no-op except on a selection change.
            let selMer = model.selectedMeridian?.id
            if selMer != highlightedMer {
                if let old = highlightedMer, let ns = channelNodes[old] {
                    BodyAtlas.setChannelHighlight(ns, meridian: old, on: false)
                }
                if let new = selMer, let ns = channelNodes[new] {
                    BodyAtlas.setChannelHighlight(ns, meridian: new, on: true)
                }
                highlightedMer = selMer
            }

            // Region brush labels: full-body mode only. All stay fully visible/tappable (they're the
            // only full-body affordance now that markers are hidden until a region/meridian is picked),
            // so they don't fade out as the figure rotates.
            if model.focused == nil && !anchors.isEmpty {
                var out: [AtlasModel.Label] = []
                for (r, node) in anchors {
                    let p = view.projectPoint(node.presentation.worldPosition)
                    guard p.z > 0 && p.z < 1 else { continue }   // in front of the camera
                    out.append(.init(id: r.id, region: r,
                                     point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), opacity: 1.0))
                }
                // Republishing an unchanged array every tick would invalidate the SwiftUI overlay
                // 30×/s while nothing moves — only publish a real change.
                if model.labels != out { model.labels = out }
            } else if !model.labels.isEmpty {
                model.labels = []
            }

            // Acupoint name tags projected onto their markers: the selected meridian's points (any
            // mode), or — while a region is focused with no card open — the region's own revealed
            // markers, so each glowing dot in the zoomed view is named ("TE3 · 中渚"). The points +
            // node lookups are cached; rebuilt only when the tag source changes, not on every
            // 30 Hz frame (the per-frame work is just the projection below).
            let tagSource: String? = {
                if let mer = model.selectedMeridian { return "mer:" + mer.id }
                if let f = model.focused, model.selectedPoint == nil { return "reg:" + f.id }
                return nil
            }()
            if let source = tagSource {
                if labeledKey != source {
                    labeledKey = source
                    if let mer = model.selectedMeridian {
                        labeledNodes = mer.points.compactMap { pt in acuNodes[pt.id].map { (pt, $0) } }
                    } else if let f = model.focused {
                        labeledNodes = acuNodes
                            .compactMap { id, node in Acupoint.byId[id].map { (pt: $0, node: node) } }
                            .filter { $0.pt.region == f.id }
                            .sorted { $0.pt.id < $1.pt.id }
                    }
                }
                // Facing fade relative to the CURRENT camera: the body never rotates — the camera
                // orbits (allowsCameraControl) — so a marker's static world z says nothing about
                // facing once the user drags. Depth along the orbit axis (orbit centre → camera)
                // equals the old world-z test exactly at the default orientation (centre at the
                // origin, camera straight down +Z) and tracks any orbit angle; the fade band
                // constants are unchanged.
                var toCam = simd_float3(0, 0, 1)
                if let pov = view.pointOfView?.presentation {
                    let c = pov.simdWorldPosition - orbitCenter
                    if simd_length(c) > 1e-4 { toCam = simd_normalize(c) }
                }
                // First gather the VISIBLE tags (after the isHidden + in-front + facing-fade culls),
                // THEN assign sides down their on-screen vertical order — so spatially adjacent tags
                // always alternate L/R (the old parity-over-the-full-array scheme stacked one side
                // whenever the visible subset shared parity, or when index order ≠ spatial order;
                // review-caught). A ±58 tag is flipped inward when it would clip the screen edge.
                struct Vis { let pt: Acupoint; let point: CGPoint; let opacity: Double }
                var vis: [Vis] = []
                for entry in labeledNodes where !entry.node.isHidden {
                    let wp = entry.node.presentation.worldPosition
                    let p = view.projectPoint(wp)
                    guard p.z > 0 && p.z < 1 else { continue }
                    let facing = simd_dot(simd_float3(wp.x, wp.y, wp.z) - orbitCenter, toCam)
                    let opacity = Double(max(0, min(1, (facing + 0.05) / 0.09)))
                    if opacity > 0.04 {
                        vis.append(Vis(pt: entry.pt, point: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)),
                                       opacity: opacity))
                    }
                }
                vis.sort { $0.point.y < $1.point.y }
                let width = view.bounds.width, margin: CGFloat = 70
                var out: [AtlasModel.PLabel] = []
                for (i, v) in vis.enumerated() {
                    var dx: CGFloat = i % 2 == 0 ? -58 : 58
                    let x = v.point.x + dx
                    if x < margin || x > width - margin { dx = -dx }   // flip inward off the edge
                    out.append(.init(id: v.pt.id, text: "\(v.pt.id) · \(AppLocale.pick(v.pt.zh, v.pt.en))",
                                     color: MeridianColors.color(v.pt.meridian),
                                     point: v.point, opacity: v.opacity, dx: dx))
                }
                if model.pointLabels != out { model.pointLabels = out }
            } else {
                if labeledKey != nil { labeledKey = nil; labeledNodes = [] }
                if !model.pointLabels.isEmpty { model.pointLabels = [] }
            }

            // Acupoint DOTS are HIDDEN until you tap a meridian channel (→ that meridian's points) or a
            // body region (→ that region's points) — the resting figure shows meridians only, uncluttered
            // (user-directed). Newly revealed dots FADE in (~0.3 s, instant under Reduce Motion); leaving
            // the selection hides them again. hitTest's nearest-first order handles occlusion on orbit.
            var revealed: [SCNNode] = []
            for (id, node) in acuNodes {
                let pt = Acupoint.byId[id]
                let inRegion = model.focused != nil && model.focused?.id == pt?.region
                let inMeridian = model.selectedMeridian != nil && model.selectedMeridian?.id == pt?.meridian
                let show = inRegion || inMeridian
                if show && node.isHidden {
                    node.isHidden = false
                    if UIAccessibility.isReduceMotionEnabled { node.opacity = 1.0 }
                    else { node.opacity = 0.0; revealed.append(node) }
                } else if !show && !node.isHidden {
                    node.isHidden = true
                    node.opacity = 1.0
                }
            }
            if !revealed.isEmpty {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                for n in revealed { n.opacity = 1.0 }
                SCNTransaction.commit()
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
            orbitCenter = simd_float3(target.x, target.y, target.z)  // facing-fade reference (tick)
        }

        func unfocus() {
            guard let spin = spin, let cam = cam else { return }
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            cam.position = SCNVector3(0, 0, radius * 11)
            cam.eulerAngles = SCNVector3Zero
            SCNTransaction.commit()
            view?.defaultCameraController.target = SCNVector3Zero    // recenter the orbit pivot
            orbitCenter = simd_float3(repeating: 0)
            spin.eulerAngles = SCNVector3Zero
        }

        // Hit-test a tap against the acupoint markers ("acu:<id>") and the meridian channels
        // ("mer:<id>"). hitTest returns results NEAREST-first, so the first match is the one facing
        // the camera at that pixel (correct at any orbit angle) — no world-axis facing hack needed.
        // A marker wins over a channel (you're tapping the point); a channel is used only if no
        // marker was hit under the tap.
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let view = view else { return }
            let loc = g.location(in: view)
            let hits = view.hitTest(loc, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            var meridianHit: String? = nil
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name {
                        if name.hasPrefix("acu:") {
                            let id = String(name.dropFirst(4))
                            if let pt = Acupoint.byId[id] {
                                model.selectedMeridian = nil
                                model.pointLabels = []
                                model.selectedPoint = pt
                            }
                            return
                        }
                        if name.hasPrefix("mer:"), meridianHit == nil {
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
