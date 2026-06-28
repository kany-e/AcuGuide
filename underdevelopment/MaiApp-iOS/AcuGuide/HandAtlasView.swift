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
                    // Hand silhouette (simple rounded outline; replace with the SVG path if desired).
                    handShape
                        .fill(LinearGradient(colors: [Color(hex: "#cdd8c0"), Color(hex: "#8a9c7b")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: box.width * scale, height: box.height * scale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    ForEach(Acupoint.all) { pt in
                        Circle()
                            .fill(MeridianColors.color(pt.meridian))
                            .frame(width: selected?.id == pt.id ? 18 : 12,
                                   height: selected?.id == pt.id ? 18 : 12)
                            .overlay(Circle().stroke(Ink.paperLight, lineWidth: 2))
                            .shadow(color: MeridianColors.color(pt.meridian).opacity(0.7), radius: 6)
                            .position(x: ox + pt.x * scale, y: oy + pt.y * scale)
                            .onTapGesture { selected = pt }
                    }
                }
            }
            if let s = selected { detailPanel(s) }
        }
        .background(Ink.paper.ignoresSafeArea())
    }

    private var handShape: some Shape { RoundedRectangle(cornerRadius: 60, style: .continuous) }

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
