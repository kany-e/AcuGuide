import SwiftUI

// 2D hand atlas — the tappable acupoint map (native port of MaiApp's HandView).
// Points are in a 360 x 440 box; we scale to fit. Tapping selects a point.
struct HandAtlasView: View {
    @State private var selected: Acupoint? = nil
    @Binding var startCoach: Acupoint?

    private let box = CGSize(width: 360, height: 440)

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let scale = min(geo.size.width / box.width, geo.size.height / box.height)
                let ox = (geo.size.width - box.width * scale) / 2
                let oy = (geo.size.height - box.height * scale) / 2
                ZStack(alignment: .topLeading) {
                    // Real hand silhouette ported from HandView.jsx: HAND_PTS → closed Catmull-Rom
                    // path, handSkin radial gradient, faint tendon/knuckle hint strokes.
                    HandSilhouette()
                        .fill(RadialGradient(
                            stops: [.init(color: Color(hex: "#cdd8c0"), location: 0),
                                    .init(color: Color(hex: "#aebd9d"), location: 0.55),
                                    .init(color: Color(hex: "#8a9c7b"), location: 1.0)],
                            center: UnitPoint(x: 0.42, y: 0.34),
                            startRadius: 0, endRadius: box.height * scale * 0.78))
                        .overlay(
                            HandTendons().stroke(Color(hex: "#6f7d61").opacity(0.45),
                                                 style: StrokeStyle(lineWidth: 1, lineCap: .round)))
                        .frame(width: box.width * scale, height: box.height * scale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    ForEach(Acupoint.all) { pt in
                        Circle()
                            .fill(MeridianColors.color(pt.meridian))
                            .frame(width: selected?.id == pt.id ? 18 : 12,
                                   height: selected?.id == pt.id ? 18 : 12)
                            .overlay(Circle().stroke(Ink.paperLight, lineWidth: 2))
                            .shadow(color: MeridianColors.color(pt.meridian).opacity(0.7), radius: 6)
                            // Center the small dot in a 44pt box → a centered 44pt tap / VoiceOver
                            // target (Shape.size is origin-anchored, so a framed box is used instead).
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .position(x: ox + pt.x * scale, y: oy + pt.y * scale)
                            .onTapGesture { selected = pt }
                            .accessibilityLabel("\(pt.id) \(pt.zh), \(pt.meridianName)")
                            .accessibilityHint("Shows the point details")
                            .accessibilityAddTraits(selected?.id == pt.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            if let s = selected { detailPanel(s) }
        }
        .background(Ink.paper.ignoresSafeArea())
    }

    private func detailPanel(_ s: Acupoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(s.id) · \(s.zh)").font(.headline).foregroundStyle(Ink.gold)
                Text("\(s.en) · \(s.pinyin)").font(.subheadline).foregroundStyle(Ink.textDim)
                Spacer()
            }
            // Meridian chip in its channel color.
            HStack(spacing: 6) {
                Circle().fill(MeridianColors.color(s.meridian)).frame(width: 9, height: 9)
                Text(s.meridianName).font(.caption).foregroundStyle(Ink.text)
            }
            labeled(AppLocale.pick("定位", "Location"), s.location)
            labeled(AppLocale.pick("传统用途", "Traditional uses"), s.indications)

            if s.mediapipeTarget != nil {
                Button(AppLocale.pick("用相机练习", "Practice with camera")) { startCoach = s }
                    .buttonStyle(GoldButtonStyle())
            } else {
                Text(AppLocale.pick("本版本仅 TE3 提供相机引导。",
                                    "Camera coaching is available for TE3 in this build."))
                    .font(.caption).foregroundStyle(Ink.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().panel().padding()
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Ink.gold).textCase(.uppercase)
            Text(value).font(.subheadline).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// The hand outline from HandView.jsx (HAND_PTS), rendered as a closed Catmull-Rom path in the
// same 360 × 440 box and scaled to fit. Control points: c1 = p1 + (p2−p0)/6, c2 = p2 − (p3−p1)/6.
struct HandSilhouette: Shape {
    static let box = CGSize(width: 360, height: 440)
    static let pts: [CGPoint] = [
        CGPoint(x: 140, y: 430), CGPoint(x: 136, y: 360), CGPoint(x: 134, y: 300), CGPoint(x: 137, y: 272), CGPoint(x: 141, y: 250),
        CGPoint(x: 130, y: 232), CGPoint(x: 114, y: 222), CGPoint(x: 99, y: 208), CGPoint(x: 91, y: 196), CGPoint(x: 88, y: 188), CGPoint(x: 95, y: 180), CGPoint(x: 111, y: 182), CGPoint(x: 128, y: 189),
        CGPoint(x: 137, y: 172), CGPoint(x: 142, y: 150), CGPoint(x: 140, y: 96), CGPoint(x: 143, y: 78), CGPoint(x: 152, y: 72), CGPoint(x: 161, y: 78), CGPoint(x: 164, y: 96), CGPoint(x: 166, y: 150),
        CGPoint(x: 170, y: 162), CGPoint(x: 172, y: 146), CGPoint(x: 170, y: 60), CGPoint(x: 173, y: 50), CGPoint(x: 182, y: 45), CGPoint(x: 191, y: 50), CGPoint(x: 194, y: 62), CGPoint(x: 196, y: 146),
        CGPoint(x: 200, y: 160), CGPoint(x: 202, y: 143), CGPoint(x: 200, y: 72), CGPoint(x: 203, y: 60), CGPoint(x: 211, y: 55), CGPoint(x: 219, y: 60), CGPoint(x: 222, y: 74), CGPoint(x: 224, y: 144),
        CGPoint(x: 228, y: 158), CGPoint(x: 230, y: 141), CGPoint(x: 229, y: 108), CGPoint(x: 231, y: 98), CGPoint(x: 238, y: 94), CGPoint(x: 244, y: 100), CGPoint(x: 246, y: 112), CGPoint(x: 248, y: 150),
        CGPoint(x: 244, y: 200), CGPoint(x: 238, y: 250), CGPoint(x: 231, y: 272), CGPoint(x: 226, y: 300), CGPoint(x: 224, y: 360), CGPoint(x: 220, y: 430),
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.box.width, sy = rect.height / Self.box.height
        func tx(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy) }
        let p = Self.pts, n = p.count
        var path = Path()
        guard n >= 3 else { return path }
        path.move(to: tx(p[0]))
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: tx(p2), control1: tx(c1), control2: tx(c2))
        }
        path.closeSubpath()
        return path
    }
}

// Faint tendon / knuckle hint strokes (the <g> in HandView.jsx), in the same 360 × 440 box.
struct HandTendons: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / HandSilhouette.box.width, sy = rect.height / HandSilhouette.box.height
        func tx(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        for (a, b) in [((150.0, 250.0), (156.0, 200.0)), ((172, 250), (176, 196)),
                       ((196, 250), (196, 196)), ((220, 250), (216, 200))] {
            path.move(to: tx(a.0, a.1)); path.addLine(to: tx(b.0, b.1))
        }
        // M150 196 q24 -10 70 0  → control (174,186), end (220,196)
        path.move(to: tx(150, 196))
        path.addQuadCurve(to: tx(220, 196), control: tx(174, 186))
        return path
    }
}
