import Vision
import CoreGraphics
@testable import AcuGuide

// THE ONE SYNTHETIC HAND the engine tests run against.
//
// There used to be eight copies of it across five files, and every copy was a MIRROR IMAGE of what
// a device actually produces: thumb at smaller x with a `.right` chirality label, where the real
// captures in claude-deliverables/data/te3_labels_2026-07-07.jsonl put a `.right` hand's thumb at
// LARGER x. That inversion is why 68 lines across those files had to force
// `HandCalibration.dorsalWhenSignedPositive = true` — the opposite of the shipped value — just to
// make a dorsal point read as dorsal.
//
// The cost was not the duplication. It was that the entire engine suite ran in a coordinate parity
// that never occurs on a phone, so the branch deciding "turn your hand over" had NO coverage at its
// shipped value, and a real inversion could not have failed a test. A user reported exactly that
// symptom before anything here did.
//
// So: one fixture, in DEVICE parity, and no test touches the calibration flag. If a change to
// isDorsal or its sign convention breaks the gate, these tests now break with it.
enum HandFixture {

    /// A DORSAL right hand, front camera, mirrored preview coordinates (top-left origin, fingers
    /// up, wrist below) — the pose and parity of the nine TE3 device captures. Under the shipped
    /// convention this reads `isDorsal == true`, which is what makes TE3 coachable in these tests.
    static let dorsalRight: [HandJoint: CGPoint] = [
        .wrist:     CGPoint(x: 0.50, y: 0.80),
        .indexMCP:  CGPoint(x: 0.56, y: 0.55),
        .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP:   CGPoint(x: 0.44, y: 0.54),
        .pinkyMCP:  CGPoint(x: 0.38, y: 0.58),
        .indexTip:  CGPoint(x: 0.58, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27),
        .ringTip:   CGPoint(x: 0.42, y: 0.30),
        .pinkyTip:  CGPoint(x: 0.34, y: 0.36),
        .thumbTip:  CGPoint(x: 0.66, y: 0.62),
    ]

    /// The SAME hand turned over — a palmar right hand, which fails the face gate for a dorsal
    /// point. Mirroring x is what physically turning a hand over looks like to the camera, so a
    /// test that needs a wrong-face frame flips the HAND rather than reaching for
    /// HandCalibration.dorsalWhenSignedPositive. Toggling that global tested the toggle, not the
    /// gate, and it is the reason no test noticed the shipped convention was uncovered.
    static let palmarRight: [HandJoint: CGPoint] =
        dorsalRight.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) }

    /// The receiving hand as the engine sees it.
    static func receiver(_ chirality: VNChirality = .right) -> Hand {
        Hand(points: dorsalRight, chirality: chirality)
    }

    /// The massaging hand, pressing at `tip` with `finger`. Its wrist sits down-and-away so the
    /// role assignment can tell the two hands apart by wrist proximity.
    /// `weak` models the foreshortened mid-press read Vision routinely drops to (0.3–0.5).
    static func presser(at tip: CGPoint, finger: HandJoint = .indexTip, weak: Bool = false,
                        wristOffset: CGVector = CGVector(dx: 0.20, dy: 0.28)) -> Hand {
        var pts: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: tip.x + wristOffset.dx, y: tip.y + wristOffset.dy),
            .middleMCP: CGPoint(x: tip.x + wristOffset.dx * 0.8, y: tip.y + wristOffset.dy * 0.7),
        ]
        pts[finger] = tip
        return Hand(points: pts, chirality: .left, weak: weak,
                    detectionConfidence: weak ? 0.35 : 0.9)
    }
}
