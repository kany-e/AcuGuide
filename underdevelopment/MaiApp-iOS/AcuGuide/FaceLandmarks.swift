import Vision
import CoreGraphics

// Face/head module — the first whole-body extension beyond the hand (see
// references/ar_coach_hand_targets.md + the whole-body research). Vision's face-landmark request
// gives eyebrow/eye/nose contours; the head acupoints are placed by the SAME proportional (cun)
// method the hand uses, anchored to those landmarks — the FaceAtlasAR approach, validated at ~95%
// for facial points.
//
// Only FACE-VISIBLE head points can be anchored from a front camera:
//   • EX-HN3 印堂 (Yintang) — glabella, midway between the medial ends of the eyebrows.
//   • EX-HN5 太阳 (Taiyang) — each temple, ~1 cun lateral-posterior to the brow-end/outer-eye midpoint.
// GV20 百会 / EX-HN1 四神聪 sit on the crown (vertex) — outside a front-face view — so they are NOT
// placed here; the body atlas + 3D head chart cover them instead.
enum FaceAcupoints {
    static let locatableIDs: Set<String> = ["EX-HN3", "EX-HN5"]
    static func isLocatable(_ id: String) -> Bool { locatableIDs.contains(id) }

    struct Mark: Identifiable { let id = UUID(); let acuId: String; let label: String; let point: CGPoint }

    // Normalized TOP-LEFT-origin marks for the visible head acupoints from one face observation.
    // `mirrored` flips x to match the mirrored (selfie) preview, exactly like the hand path.
    static func marks(from face: VNFaceObservation, mirrored: Bool) -> [Mark] {
        guard let lm = face.landmarks,
              let lBrow = lm.leftEyebrow?.normalizedPoints, !lBrow.isEmpty,
              let rBrow = lm.rightEyebrow?.normalizedPoints, !rBrow.isEmpty,
              let lEye = lm.leftEye?.normalizedPoints, !lEye.isEmpty,
              let rEye = lm.rightEye?.normalizedPoints, !rEye.isEmpty
        else { return [] }
        let bb = face.boundingBox   // normalized, bottom-left origin

        // Landmark region points are normalized to the face bbox (0…1, y-up). Midline ≈ x 0.5.
        func nearMid(_ p: [CGPoint]) -> CGPoint { p.min { abs($0.x - 0.5) < abs($1.x - 0.5) }! }
        func farMid(_ p: [CGPoint])  -> CGPoint { p.max { abs($0.x - 0.5) < abs($1.x - 0.5) }! }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

        // Face-space (bbox-relative, y-up) → image-normalized, top-left, mirrored to match preview.
        func toImage(_ f: CGPoint) -> CGPoint {
            var x = bb.minX + f.x * bb.width
            let yTop = 1 - (bb.minY + f.y * bb.height)   // Vision bottom-left → top-left
            if mirrored { x = 1 - x }
            return CGPoint(x: x, y: yTop)
        }

        func label(_ id: String) -> String {
            guard let p = Acupoint.byId[id] else { return id }
            return "\(p.id) · \(AppLocale.pick(p.zh, p.en))"
        }

        var out: [Mark] = []

        // Yintang: midpoint of the two inner (medial) brow ends — the glabella between the brows.
        let yin = mid(nearMid(lBrow), nearMid(rBrow))
        out.append(Mark(acuId: "EX-HN3", label: label("EX-HN3"), point: toImage(yin)))

        // Taiyang (each temple): midpoint of the lateral brow end + the outer eye corner, pushed
        // laterally-posterior toward the temple (≈1 cun) — amplify the offset from the midline.
        for (brow, eye) in [(lBrow, lEye), (rBrow, rEye)] {
            let m = mid(farMid(brow), farMid(eye))
            let taiyang = CGPoint(x: m.x + 0.35 * (m.x - 0.5), y: m.y + 0.02)
            out.append(Mark(acuId: "EX-HN5", label: label("EX-HN5"), point: toImage(taiyang)))
        }
        return out
    }
}
