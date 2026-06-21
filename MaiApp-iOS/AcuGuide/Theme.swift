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
