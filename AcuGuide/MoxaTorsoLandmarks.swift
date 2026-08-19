import Vision
import CoreGraphics

// CAMERA HELP FOR THE MOXA POINTS — the abdominal midline, and only that.
//
// The moxa tab asked people to find CV8/CV6/CV4 by measuring navel-to-pubic-bone in their own
// finger-widths, which is the correct method (骨度分寸 with 同身寸 supplying the unit) and also the
// step where a first-timer stalls. The camera cannot replace the measurement — it re-derives it,
// live, from the same proportional span, so there is something to check the hand measurement
// against.
//
// IT REUSES THE FRAME THAT ALREADY SHIPPED. TorsoAcupoints builds the WHO proportional midline from
// the two joints Vision reports on the trunk — neck (≈ suprasternal notch) → root (≈ pubic
// symphysis) — and the standard AP spans make that 22 cun total with the navel at 17. A moxa
// anchor is stored as a fraction of the navel→pubicBorder span, which is the last 5 cun of exactly
// that line. So this is arithmetic on a shipped frame, not a second body model:
//
//     t = (17 + 5·fraction) / 22
//
// WHICH POINTS, AND WHY IT IS DERIVED RATHER THAN LISTED. A point is camera-locatable iff its
// anchor is measured along navel→pubicBorder and sits on the midline. That excludes the lumbar
// points structurally rather than by a maintained list: they are anchored to the iliac-crest line,
// they are on the BACK where a selfie preview cannot see them, and their own data already says
// `drawAsArea` because palpating the crest runs one to two vertebral levels high — 3.5 to 7 cm.
// A dot drawn on a live picture from that landmark would be false precision on a heat source.
enum MoxaTorsoAcupoints {
    /// Total length of the neck→root line in cun, and where the navel falls on it — the same
    /// numbers TorsoAcupoints uses, named here so the arithmetic below reads as anatomy.
    private static let trunkCun = 22.0
    private static let navelCun = 17.0
    /// navel → pubic border, the span every abdominal moxa anchor is a fraction OF (WHO 2008;
    /// GB/T 12346—2021 agrees).
    private static let navelToPubis = 5.0

    /// Can the camera place this point at all? Derived from the anchor, so a new point is answered
    /// by its own data and the lumbar points can never drift into the camera path.
    static func isLocatable(_ p: MoxaPoint) -> Bool {
        p.anchor.from == .navel && p.anchor.to == .pubicBorder && !p.anchor.bilateral
    }

    static var locatable: [MoxaPoint] { MoxaAtlas.all.filter(isLocatable) }

    /// Where this point falls on the neck→root line, as a fraction of it.
    static func trunkFraction(_ p: MoxaPoint) -> Double {
        (navelCun + navelToPubis * p.anchor.fraction) / trunkCun
    }

    /// Marks for every camera-locatable moxa point, in the preview's normalized (top-left) space.
    /// `focus` is drawn like the rest — the overlay enlarges it — so the neighbours stay visible:
    /// on this span the neighbours ARE the sanity check (Shenque at the navel and Guanyuan at 0.60
    /// bracket Qihai, and a box covering two of them is the thing the placement copy warns about).
    static func marks(from body: VNHumanBodyPoseObservation, aspect fa: CGFloat,
                      mirrored: Bool) -> [LocatorMark] {
        func pt(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? body.recognizedPoint(j), p.confidence > 0.3 else { return nil }
            return CGPoint(x: p.location.x, y: 1 - p.location.y)   // top-left, not yet mirrored
        }
        guard let neck = pt(.neck), let root = pt(.root) else { return [] }

        // Aspect-correct to isotropic (height-fraction) units so one cun is the same length in x
        // and y — the same correction TorsoAcupoints makes, and for the same reason.
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * fa, y: p.y) }
        func unIso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / fa, y: p.y) }
        let n = iso(neck), r = iso(root)
        let vx = r.x - n.x, vy = r.y - n.y
        let len = (vx * vx + vy * vy).squareRoot()
        guard len > 0.10 else { return [] }        // trunk not framed large enough to mean anything

        return locatable.map { p in
            let t = CGFloat(trunkFraction(p))
            var q = unIso(CGPoint(x: n.x + vx * t, y: n.y + vy * t))
            if mirrored { q.x = 1 - q.x }
            return LocatorMark(acuId: p.id, label: "\(p.id) · \(p.name)", point: q, meridianKey: "ren")
        }
    }
}
