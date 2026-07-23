import Vision
import CoreGraphics

// Torso/abdomen module — the third region (after hand + face). Vision body pose gives no navel or
// sternum, so we build the WHO proportional bone-cun midline from the two joints it does report:
// neck (≈ suprasternal notch) → root (≈ pubic symphysis). Standard AP spans: notch→xiphoid 9 cun,
// xiphoid→navel 8, navel→pubis 5 → 22 cun total. So the navel sits 17/22 down that line, and points
// are placed by cun fraction. The torso is the hardest region (soft tissue, breathing, clothing, and
// the cun standard itself is imperfect there) — this is a guidance ESTIMATE, not clinical precision.
enum TorsoAcupoints {
    static let locatableIDs: Set<String> = ["CV12", "ST25"]
    static func isLocatable(_ id: String) -> Bool { locatableIDs.contains(id) }

    static func marks(from body: VNHumanBodyPoseObservation, aspect fa: CGFloat, mirrored: Bool) -> [LocatorMark] {
        func pt(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? body.recognizedPoint(j), p.confidence > 0.3 else { return nil }
            return CGPoint(x: p.location.x, y: 1 - p.location.y)   // top-left, not yet mirrored
        }
        guard let neck = pt(.neck), let root = pt(.root) else { return [] }

        // Aspect-correct to isotropic (height-fraction) units so 1 cun is equal in x and y.
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * fa, y: p.y) }
        func unIso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / fa, y: p.y) }
        let n = iso(neck), r = iso(root)
        let vx = r.x - n.x, vy = r.y - n.y
        let len = (vx * vx + vy * vy).squareRoot()
        guard len > 0.10 else { return [] }        // torso not framed large enough to be meaningful
        let cun = len / 22.0
        func along(_ t: CGFloat) -> CGPoint { CGPoint(x: n.x + vx * t, y: n.y + vy * t) }
        let navel = along(17.0 / 22.0)
        let cv12  = along(13.0 / 22.0)             // Zhongwan: 4 cun above the navel
        let px = -vy / len, py = vx / len          // unit perpendicular to the midline (lateral)

        func mark(_ p: CGPoint, _ id: String) -> LocatorMark {
            var q = unIso(p)
            if mirrored { q.x = 1 - q.x }
            let a = Acupoint.byId[id]
            return LocatorMark(acuId: id, label: a.map { "\($0.id) · \(AppLocale.pick($0.zh, $0.en))" } ?? id, point: q)
        }

        let d = 2 * cun                            // Tianshu: 2 cun lateral to the navel, both sides
        return [
            mark(cv12, "CV12"),
            mark(CGPoint(x: navel.x + px * d, y: navel.y + py * d), "ST25"),
            mark(CGPoint(x: navel.x - px * d, y: navel.y - py * d), "ST25"),
        ]
    }
}
