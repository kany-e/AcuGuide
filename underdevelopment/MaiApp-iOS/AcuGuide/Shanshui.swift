import SwiftUI

// Decorative shanshui (山水) backdrop — place behind EVERY page so the theme is identical
// everywhere and DRY. Mirrors styles.css `body` + the fixed `.ink-bg` (moon, mountains, mist).
// Purely decorative: `.allowsHitTesting(false)` so it never intercepts taps.
struct ShanshuiBackground: View {
    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()                              // parchment ground

            GeometryReader { geo in                                   // moon, top-trailing
                Circle()
                    .fill(RadialGradient(
                        stops: [
                            .init(color: Ink.moonCore,            location: 0.00),
                            .init(color: Ink.moonEdge,            location: 0.58),
                            .init(color: Ink.moonEdge.opacity(0), location: 0.72),
                        ],
                        center: UnitPoint(x: 0.42, y: 0.40), startRadius: 0, endRadius: 65))
                    .frame(width: 130, height: 130)
                    .blur(radius: 2).opacity(0.18)
                    .position(x: geo.size.width * 0.84, y: geo.size.height * 0.10)
            }
            .ignoresSafeArea()

            GeometryReader { geo in                                   // mountains, bottom 60%
                let bandH = geo.size.height * 0.60
                ZStack(alignment: .bottom) {
                    MountainsShape(ridge: .far ).fill(Ink.mtnFar ).frame(height: bandH)
                    MountainsShape(ridge: .mid ).fill(Ink.mtnMid ).frame(height: bandH)
                    MountainsShape(ridge: .near).fill(Ink.mtnNear).frame(height: bandH)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .ignoresSafeArea()

            EllipticalGradient(                                       // mist wash, upper
                stops: [.init(color: Ink.mist1, location: 0), .init(color: Ink.mist1.opacity(0), location: 0.58)],
                center: UnitPoint(x: 0.5, y: 0.24)).ignoresSafeArea()
            EllipticalGradient(                                       // mist wash, lower
                stops: [.init(color: Ink.mist2, location: 0), .init(color: Ink.mist2.opacity(0), location: 0.62)],
                center: UnitPoint(x: 0.5, y: 1.0)).ignoresSafeArea()
        }
        .allowsHitTesting(false)                                      // purely decorative
    }
}

// Three ink ridgelines, ported verbatim from MeridianAtlas.jsx (viewBox 0 0 1440 700).
struct MountainsShape: Shape {
    enum Ridge { case far, mid, near }
    let ridge: Ridge
    func path(in rect: CGRect) -> Path {
        let vbW: CGFloat = 1440, vbH: CGFloat = 700
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / vbW * rect.width, y: y / vbH * rect.height) }
        var p = Path()
        switch ridge {
        case .far:
            p.move(to: P(0, 430))
            p.addCurve(to: P(470, 356),  control1: P(160, 372),  control2: P(320, 398))
            p.addCurve(to: P(1000, 300), control1: P(640, 308),  control2: P(800, 236))
            p.addCurve(to: P(1440, 360), control1: P(1160, 350), control2: P(1300, 330))
        case .mid:
            p.move(to: P(0, 520))
            p.addCurve(to: P(540, 470),  control1: P(200, 478),  control2: P(360, 500))
            p.addCurve(to: P(1110, 452), control1: P(740, 436),  control2: P(900, 402))
            p.addCurve(to: P(1440, 498), control1: P(1270, 490), control2: P(1370, 476))
        case .near:
            p.move(to: P(0, 612))
            p.addCurve(to: P(650, 586),  control1: P(240, 588),  control2: P(430, 602))
            p.addCurve(to: P(1250, 582), control1: P(870, 570),  control2: P(1030, 560))
            p.addCurve(to: P(1440, 592), control1: P(1350, 592), control2: P(1410, 588))
        }
        p.addLine(to: P(1440, 700)); p.addLine(to: P(0, 700)); p.closeSubpath()
        return p
    }
}
