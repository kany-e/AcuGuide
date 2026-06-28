import SwiftUI

// Ink-and-gold palette, matched 1:1 to MaiApp's styles.css :root tokens so the
// native app is visually consistent with the web atlas.
extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var v: UInt64 = 0
        s.scanHexInt64(&v)
        let r, g, b, a: Double
        if hex.count > 7 { // #RRGGBBAA
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Ink {
    static let paper      = Color(hex: "#ece9e0")  // --ink
    static let paperLight = Color(hex: "#f4f2ea")  // --ink-2
    static let gold       = Color(hex: "#9a7d44")  // --gold
    static let goldSoft   = Color(hex: "#7c6531")  // --gold-soft
    static let jade       = Color(hex: "#5f8a63")  // --jade
    static let parch      = Color(hex: "#2f332c")  // --parch (deep ground)
    static let text       = Color(hex: "#33372f")  // --text
    static let textDim    = Color(hex: "#767b6e")  // --text-dim
    static let line       = Color(hex: "#5a5032").opacity(0.22) // --line
    static let terracotta = Color(hex: "#b04a2f")  // accent (BUILD tag / alerts)
    static let highlight  = Color(hex: "#fff3d6")  // warm highlight

    // Feedback colors for the AR coach (kept on-palette, not generic RGB).
    static let good   = jade          // on-target / holding
    static let warn   = terracotta    // wrong place / wrong face
    static let hint   = gold          // searching / coaching
}

// Reusable parchment panel + gold button, used across atlas / hand / AR / chat.
struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Ink.paperLight)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.line, lineWidth: 1))
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 12).padding(.horizontal, 22)
            .foregroundStyle(Ink.paperLight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? Ink.goldSoft : Ink.gold)
            )
    }
}

// MARK: - Shanshui (山水) light theme — matched 1:1 to MaiApp styles.css.
// Every page sits on this light parchment ground (see ShanshuiBackground); foreground text
// uses Ink.text. Ink.parch is retired as a page background — there is no dark page anymore.
extension Ink {
    // Page ground: parchment radial gradient (styles.css `body`).
    static let groundTop  = Color(hex: "#f6f4ed")   // 0%
    static let groundMid  = Color(hex: "#ece9e0")   // 55%  (== Ink.paper / --ink)
    static let groundEdge = Color(hex: "#e1dfd4")   // 100%
    static var ground: EllipticalGradient {         // ≈ radial 120% 90% at 50% 0%
        EllipticalGradient(
            stops: [
                .init(color: groundTop,  location: 0.00),
                .init(color: groundMid,  location: 0.55),
                .init(color: groundEdge, location: 1.00),
            ],
            center: .top,                 // "at 50% 0%"
            startRadiusFraction: 0.0,
            endRadiusFraction: 1.0)
    }

    // Moon (.ink-bg .moon): radial #d8d2c2 → #c3bda9 58% → clear 72%.
    static let moonCore = Color(hex: "#d8d2c2")
    static let moonEdge = Color(hex: "#c3bda9")

    // Shanshui ink mountains (.mtn-far/mid/near) — alpha baked in.
    static let mtnFar  = Color(hex: "#606e62").opacity(0.10)   // rgba(96,110,98,.10)
    static let mtnMid  = Color(hex: "#4e5c50").opacity(0.13)   // rgba(78,92,80,.13)
    static let mtnNear = Color(hex: "#3c4a3e").opacity(0.17)   // rgba(60,74,62,.17)

    // Mist (.ink-bg .mist), two soft washes.
    static let mist1 = Color(hex: "#96a596").opacity(0.20)     // rgba(150,165,150,.20)
    static let mist2 = Color(hex: "#788270").opacity(0.18)     // rgba(120,130,112,.18)

    // Ink brush region labels (.brush-label / .sm / .soft).
    static let brush     = Color(hex: "#3a4234")
    static let brushSoft = Color(hex: "#4a5340")

    // 3D body material (Body3D.jsx: sage diffuse + low emissive).
    static let bodySage     = Color(hex: "#aebd9d")
    static let bodyEmission = Color(hex: "#2c3626")
}
