import AppKit
import CoreText

// AcuGuide app-icon generator — classical-TCM-chart aesthetic on the app's shanshui palette:
// parchment ground, ink mountains + moon, an ink meridian-chart figure (or hand) with a gold
// channel + acupoint dots, and a red seal stamp. Emits opaque 1024×1024 PNGs (App Store master).

let S: CGFloat = 1024

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

let groundTop = hex(0xf6f4ed), groundMid = hex(0xece9e0), groundEdge = hex(0xdcd9cc)
let ink = hex(0x3a4234), gold = hex(0x9a7d44), goldSoft = hex(0x7c6531)
let terra = hex(0xb04a2f), highlight = hex(0xfff3d6), moonC = hex(0xd8d2c2)

func ctx() -> CGContext {
    let c = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // OPAQUE (App Store rule)
    c.translateBy(x: 0, y: S); c.scaleBy(x: 1, y: -1)                        // design in top-left coords
    return c
}

func save(_ c: CGContext, _ path: String) {
    let img = c.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

// ── shared scenery ────────────────────────────────────────────────────────────
func parchment(_ c: CGContext) {
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [groundTop, groundMid, groundEdge] as CFArray,
                          locations: [0, 0.55, 1])!
    c.drawRadialGradient(grad, startCenter: CGPoint(x: S/2, y: S*0.30), startRadius: 0,
                         endCenter: CGPoint(x: S/2, y: S*0.42), endRadius: S*0.85, options: [.drawsAfterEndLocation])
}

func moon(_ c: CGContext, at p: CGPoint, r: CGFloat) {
    c.setFillColor(hex(0xd8d2c2, 0.45))
    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r))
    c.setStrokeColor(hex(0xc3bda9, 0.5)); c.setLineWidth(3)
    c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r))
}

func mountains(_ c: CGContext) {
    func mound(_ cx: CGFloat, _ top: CGFloat, _ w: CGFloat, _ col: CGColor) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx - w, y: S))
        p.addQuadCurve(to: CGPoint(x: cx, y: top), control: CGPoint(x: cx - w*0.45, y: top + 30))
        p.addQuadCurve(to: CGPoint(x: cx + w, y: S), control: CGPoint(x: cx + w*0.45, y: top + 30))
        p.closeSubpath()
        c.setFillColor(col); c.addPath(p); c.fillPath()
    }
    mound(S*0.22, S*0.80, S*0.42, hex(0x606e62, 0.10))
    mound(S*0.80, S*0.76, S*0.46, hex(0x4e5c50, 0.12))
    mound(S*0.52, S*0.84, S*0.55, hex(0x3c4a3e, 0.15))
}

func seal(_ c: CGContext, rect: CGRect, char: String, fontSize: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil)
    c.setFillColor(terra); c.addPath(path); c.fillPath()
    let inner = rect.insetBy(dx: 11, dy: 11)
    c.setStrokeColor(hex(0xffffff, 0.35)); c.setLineWidth(4)
    c.addPath(CGPath(roundedRect: inner, cornerWidth: 12, cornerHeight: 12, transform: nil)); c.strokePath()

    let font = ["Xingkai SC", "Kaiti SC", "STKaiti", "PingFang SC"]
        .compactMap { NSFont(name: $0, size: fontSize) }.first ?? NSFont.systemFont(ofSize: fontSize)
    let attr = NSAttributedString(string: char, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: hex(0xfef6ea))!])
    let line = CTLineCreateWithAttributedString(attr)
    let b = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    c.saveGState()
    c.translateBy(x: rect.midX - b.midX, y: rect.midY + b.midY)   // account for flipped ctx
    c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero
    CTLineDraw(line, c)
    c.restoreGState()
}

// Acupoint dot: soft gold halo + gold ring + warm core.
func dot(_ c: CGContext, _ p: CGPoint, r: CGFloat = 13) {
    c.setFillColor(hex(0x9a7d44, 0.28))
    c.fillEllipse(in: CGRect(x: p.x - r*1.9, y: p.y - r*1.9, width: r*3.8, height: r*3.8))
    c.setFillColor(highlight)
    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r))
    c.setStrokeColor(gold); c.setLineWidth(r * 0.42)
    c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r))
}

func stroke(_ c: CGContext, _ pts: [CGPoint], w: CGFloat, col: CGColor) {
    c.setStrokeColor(col); c.setLineWidth(w); c.setLineCap(.round); c.setLineJoin(.round)
    c.beginPath(); c.move(to: pts[0]); for p in pts.dropFirst() { c.addLine(to: p) }
    c.strokePath()
}

// ── Variant A: meridian-chart figure ─────────────────────────────────────────
func variantA(_ out: String) {
    let c = ctx()
    parchment(c); moon(c, at: CGPoint(x: 218, y: 200), r: 78); mountains(c)

    // Ink woodcut figure: head + limb strokes + torso block.
    c.setFillColor(ink)
    c.fillEllipse(in: CGRect(x: 512 - 56, y: 176, width: 112, height: 112))            // head
    c.fill(CGRect(x: 494, y: 278, width: 36, height: 34))                              // neck
    let torso = CGPath(roundedRect: CGRect(x: 436, y: 300, width: 152, height: 320),
                       cornerWidth: 62, cornerHeight: 62, transform: nil)
    c.addPath(torso); c.fillPath()
    stroke(c, [CGPoint(x: 452, y: 342), CGPoint(x: 414, y: 470), CGPoint(x: 398, y: 592)], w: 42, col: ink) // L arm
    stroke(c, [CGPoint(x: 572, y: 342), CGPoint(x: 610, y: 470), CGPoint(x: 626, y: 592)], w: 42, col: ink) // R arm
    stroke(c, [CGPoint(x: 482, y: 596), CGPoint(x: 470, y: 838)], w: 54, col: ink)     // L leg
    stroke(c, [CGPoint(x: 542, y: 596), CGPoint(x: 554, y: 838)], w: 54, col: ink)     // R leg

    // Gold channels: the midline (Ren/Du) + one arm channel each side + leg lines.
    stroke(c, [CGPoint(x: 512, y: 232), CGPoint(x: 512, y: 600)], w: 7, col: hex(0x9a7d44, 0.9))
    stroke(c, [CGPoint(x: 455, y: 348), CGPoint(x: 417, y: 472), CGPoint(x: 401, y: 586)], w: 5, col: hex(0x9a7d44, 0.85))
    stroke(c, [CGPoint(x: 569, y: 348), CGPoint(x: 607, y: 472), CGPoint(x: 623, y: 586)], w: 5, col: hex(0x9a7d44, 0.85))
    stroke(c, [CGPoint(x: 482, y: 620), CGPoint(x: 471, y: 826)], w: 5, col: hex(0x9a7d44, 0.85))
    stroke(c, [CGPoint(x: 542, y: 620), CGPoint(x: 553, y: 826)], w: 5, col: hex(0x9a7d44, 0.85))

    // Acupoint dots: crown, brow, chest, abdomen midline; elbow + wrist each arm; ankles.
    dot(c, CGPoint(x: 512, y: 176), r: 15)          // GV20 crown
    dot(c, CGPoint(x: 512, y: 352), r: 13)
    dot(c, CGPoint(x: 512, y: 452), r: 13)
    dot(c, CGPoint(x: 512, y: 552), r: 13)
    dot(c, CGPoint(x: 417, y: 472), r: 11); dot(c, CGPoint(x: 401, y: 586), r: 11)
    dot(c, CGPoint(x: 607, y: 472), r: 11); dot(c, CGPoint(x: 623, y: 586), r: 11)
    dot(c, CGPoint(x: 471, y: 800), r: 10); dot(c, CGPoint(x: 553, y: 800), r: 10)

    seal(c, rect: CGRect(x: 712, y: 712, width: 180, height: 180), char: "脉", fontSize: 128)
    save(c, out)
}

// ── Variant B: hand chart (the app's signature interaction) ──────────────────
func variantB(_ out: String) {
    let c = ctx()
    parchment(c); moon(c, at: CGPoint(x: 790, y: 200), r: 72); mountains(c)

    c.setFillColor(ink)
    // Palm + wrist
    let palm = CGPath(roundedRect: CGRect(x: 352, y: 470, width: 320, height: 300),
                      cornerWidth: 92, cornerHeight: 92, transform: nil)
    c.addPath(palm); c.fillPath()
    stroke(c, [CGPoint(x: 512, y: 740), CGPoint(x: 512, y: 900)], w: 190, col: ink)    // wrist stub
    // Fingers (index → pinky), thumb.
    stroke(c, [CGPoint(x: 402, y: 500), CGPoint(x: 388, y: 268)], w: 62, col: ink)
    stroke(c, [CGPoint(x: 478, y: 496), CGPoint(x: 474, y: 226)], w: 64, col: ink)
    stroke(c, [CGPoint(x: 554, y: 498), CGPoint(x: 562, y: 246)], w: 62, col: ink)
    stroke(c, [CGPoint(x: 624, y: 512), CGPoint(x: 642, y: 320)], w: 56, col: ink)
    stroke(c, [CGPoint(x: 380, y: 640), CGPoint(x: 268, y: 520)], w: 66, col: ink)     // thumb

    // Gold channel: wrist → between ring/little knuckles (the TE3 line), + a midline.
    stroke(c, [CGPoint(x: 540, y: 880), CGPoint(x: 596, y: 560), CGPoint(x: 634, y: 380)], w: 7, col: hex(0x9a7d44, 0.9))
    stroke(c, [CGPoint(x: 500, y: 880), CGPoint(x: 478, y: 420)], w: 5, col: hex(0x9a7d44, 0.7))
    // Dots: TE3 (hero, largest), TE4 wrist, knuckle point.
    dot(c, CGPoint(x: 596, y: 560), r: 17)          // TE3 hero
    dot(c, CGPoint(x: 540, y: 806), r: 12)
    dot(c, CGPoint(x: 478, y: 470), r: 11)

    seal(c, rect: CGRect(x: 128, y: 132, width: 172, height: 172), char: "穴", fontSize: 120)
    save(c, out)
}

// ── Variant C: seal + enso (minimal) ──────────────────────────────────────────
func variantC(_ out: String) {
    let c = ctx()
    parchment(c); mountains(c)
    // Ink enso ring (brush circle with a gap), gold acupoint on the ring.
    c.setStrokeColor(hex(0x3a4234, 0.88)); c.setLineWidth(34); c.setLineCap(.round)
    c.addArc(center: CGPoint(x: 512, y: 470), radius: 268,
             startAngle: -.pi * 0.42, endAngle: .pi * 1.28, clockwise: false)
    c.strokePath()
    dot(c, CGPoint(x: 512 + 268 * cos(-.pi * 0.42), y: 470 + 268 * sin(-.pi * 0.42)), r: 20)
    seal(c, rect: CGRect(x: 388, y: 356, width: 248, height: 248), char: "脉", fontSize: 178)
    save(c, out)
}

// ── Variant A2: refined chart figure — larger, connected head, chart pose, fewer/larger dots ──
func variantA2(_ out: String) {
    let c = ctx()
    parchment(c); moon(c, at: CGPoint(x: 196, y: 178), r: 64); mountains(c)

    c.setFillColor(ink)
    c.fillEllipse(in: CGRect(x: 512 - 64, y: 132, width: 128, height: 128))            // head
    // Neck→shoulders as one trapezoid so the head reads connected.
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: 486, y: 236)); neck.addLine(to: CGPoint(x: 538, y: 236))
    neck.addLine(to: CGPoint(x: 574, y: 300)); neck.addLine(to: CGPoint(x: 450, y: 300))
    neck.closeSubpath(); c.addPath(neck); c.fillPath()
    let torso = CGPath(roundedRect: CGRect(x: 424, y: 278, width: 176, height: 360),
                       cornerWidth: 70, cornerHeight: 70, transform: nil)
    c.addPath(torso); c.fillPath()
    // Chart pose: arms angled outward like the classical woodcuts.
    stroke(c, [CGPoint(x: 444, y: 324), CGPoint(x: 380, y: 468), CGPoint(x: 352, y: 620)], w: 48, col: ink)
    stroke(c, [CGPoint(x: 580, y: 324), CGPoint(x: 644, y: 468), CGPoint(x: 672, y: 620)], w: 48, col: ink)
    stroke(c, [CGPoint(x: 478, y: 616), CGPoint(x: 462, y: 896)], w: 62, col: ink)
    stroke(c, [CGPoint(x: 546, y: 616), CGPoint(x: 562, y: 896)], w: 62, col: ink)

    // Channels: bold midline + arm lines + leg lines (gold).
    stroke(c, [CGPoint(x: 512, y: 196), CGPoint(x: 512, y: 620)], w: 8, col: hex(0x9a7d44, 0.92))
    stroke(c, [CGPoint(x: 447, y: 330), CGPoint(x: 383, y: 470), CGPoint(x: 356, y: 612)], w: 6, col: hex(0x9a7d44, 0.85))
    stroke(c, [CGPoint(x: 577, y: 330), CGPoint(x: 641, y: 470), CGPoint(x: 668, y: 612)], w: 6, col: hex(0x9a7d44, 0.85))
    stroke(c, [CGPoint(x: 478, y: 640), CGPoint(x: 464, y: 880)], w: 6, col: hex(0x9a7d44, 0.8))
    stroke(c, [CGPoint(x: 546, y: 640), CGPoint(x: 560, y: 880)], w: 6, col: hex(0x9a7d44, 0.8))

    // Five dots only, large: crown, chest, dantian, both wrists — reads at 60px.
    dot(c, CGPoint(x: 512, y: 132), r: 19)
    dot(c, CGPoint(x: 512, y: 380), r: 16)
    dot(c, CGPoint(x: 512, y: 540), r: 16)
    dot(c, CGPoint(x: 356, y: 612), r: 14)
    dot(c, CGPoint(x: 668, y: 612), r: 14)

    seal(c, rect: CGRect(x: 724, y: 736, width: 178, height: 178), char: "脉", fontSize: 126)
    save(c, out)
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
variantA("\(dir)/icon_A_figure.png")
variantB("\(dir)/icon_B_hand.png")
variantC("\(dir)/icon_C_seal.png")
variantA2("\(dir)/icon_A2_figure.png")
