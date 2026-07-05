import Vision
import CoreGraphics

// The ONE place Vision hand-pose landmarks become our normalized TOP-LEFT (mirror-aware) points, so
// the live coach (CameraCoach) and the M3 label-capture harness (LabelCapture) share the EXACT same
// convention → zero train/serve skew, the localizer research's load-bearing requirement. The label a
// human clicks and the joints the head sees are then guaranteed to live in one coordinate space.
enum HandVision {
    // Feature/joint order MUST stay in lockstep with ShadowLocalizer.joints / train.py JOINTS.
    static let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                      .indexMCP, .middleMCP, .ringMCP, .pinkyMCP]

    struct Sample { var points: [HandJoint: CGPoint]; var confidence: [HandJoint: Float] }

    // Normalized TOP-LEFT points (+ per-joint Vision confidence), x-mirrored when `flipX` (to match the
    // mirrored selfie preview). Per-joint gate 0.3 == the coach's. Returns nil if the wrist wasn't found
    // (every downstream frame/handSize needs the wrist).
    static func sample(_ obs: VNHumanHandPoseObservation, flipX: Bool) -> Sample? {
        var pts: [HandJoint: CGPoint] = [:]; var conf: [HandJoint: Float] = [:]
        for j in joints {
            guard let rp = try? obs.recognizedPoint(j.vision), rp.confidence > 0.3 else { continue }
            // Vision: normalized, BOTTOM-left origin. Flip y → top-left; mirror x to match the preview.
            var x = rp.location.x
            let y = 1 - rp.location.y
            if flipX { x = 1 - x }
            pts[j] = CGPoint(x: x, y: y); conf[j] = rp.confidence
        }
        guard pts[.wrist] != nil else { return nil }
        return Sample(points: pts, confidence: conf)
    }
}
