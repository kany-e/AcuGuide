import Vision
import CoreGraphics

// The ONE place Vision hand-pose landmarks become our normalized TOP-LEFT (mirror-aware) points, so
// the live coach (CameraCoach) and the M3 label-capture harness (LabelCapture) share the EXACT same
// convention → zero train/serve skew, the localizer research's load-bearing requirement. The label a
// human clicks and the joints the head sees are then guaranteed to live in one coordinate space.
enum HandVision {
    // Extraction list for the coach + label capture. (ShadowLocalizer keeps its OWN 10-joint list —
    // that one is the trained feature order and must stay in lockstep with train.py JOINTS.)
    // indexPIP/indexDIP feed the press-tip occlusion fallback (Hand.pressTip).
    static let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                      .indexMCP, .middleMCP, .ringMCP, .pinkyMCP, .indexPIP, .indexDIP]

    struct Sample { var points: [HandJoint: CGPoint]; var confidence: [HandJoint: Float] }

    // Vision landmark → our normalized TOP-LEFT convention, as ONE pure (testable) mapping:
    // `rotated180` undoes an inverted-frame detection pass (the observation came from the buffer
    // rotated 180°, so its coords rotate back: (x,y) → (1−x, 1−y)); then Vision's bottom-left
    // origin flips to top-left; then `flipX` mirrors to match the selfie preview. A 180° rotation
    // is two mirrors — parity is PRESERVED — so chirality and the isDorsal sign stay valid.
    static func normalize(_ loc: CGPoint, rotated180: Bool, flipX: Bool) -> CGPoint {
        var x = loc.x, y = loc.y
        if rotated180 { x = 1 - x; y = 1 - y }
        y = 1 - y
        if flipX { x = 1 - x }
        return CGPoint(x: x, y: y)
    }

    // Normalized TOP-LEFT points (+ per-joint Vision confidence), x-mirrored when `flipX` (to match the
    // mirrored selfie preview); `rotated180` for observations from the inverted-frame pass. Per-joint
    // gate 0.3 == the coach's. Returns nil if the wrist wasn't found (every downstream frame/handSize
    // needs the wrist).
    static func sample(_ obs: VNHumanHandPoseObservation, flipX: Bool, rotated180: Bool = false) -> Sample? {
        var pts: [HandJoint: CGPoint] = [:]; var conf: [HandJoint: Float] = [:]
        for j in joints {
            guard let rp = try? obs.recognizedPoint(j.vision), rp.confidence > 0.3 else { continue }
            pts[j] = normalize(rp.location, rotated180: rotated180, flipX: flipX)
            conf[j] = rp.confidence
        }
        guard pts[.wrist] != nil else { return nil }
        return Sample(points: pts, confidence: conf)
    }
}
