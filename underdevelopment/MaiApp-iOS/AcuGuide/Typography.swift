import SwiftUI

// App typography, matched to the web app's font stack (MaiApp index.html / styles.css):
//   • Ma Shan Zheng  — brush calligraphy, used for region / meridian (穴位) labels (书法 feel)
//   • Cormorant Garamond — Latin serif, used for point codes (TE3, PC6…)
//   • Serif headings/body — the iOS system serif (CJK-capable). Noto Serif SC is intentionally
//     NOT bundled: its variable TTF is ~25 MB; the system serif covers Chinese body text.
// The two bundled fonts are registered via UIAppFonts (see project.yml → Info.plist). If a custom
// font fails to load, Font.custom falls back to the system font, so the UI never breaks.
enum Typo {
    static func brush(_ size: CGFloat) -> Font { .custom("MaShanZheng-Regular", size: size) }
    static func code(_ size: CGFloat)  -> Font { .custom("CormorantGaramond-Light", size: size) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
