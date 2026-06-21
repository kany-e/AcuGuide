import SwiftUI
import Vision

enum CoachPhase { case noHand, wrongFace, searching, onTargetUnstable, holding, paused, complete }

// Per-frame coaching engine. Mirrors the web app's useCoachingState + usePressDetection:
// position-only feedback (on the validated TE3 point) + a hold timer + steadiness.
// NO cadence/BPM (frequency was NO-GO; correct technique is a sustained press).
final class CoachEngine: ObservableObject {
    @Published var phase: CoachPhase = .noHand
    @Published var ringCenter: CGPoint? = nil      // normalized, top-left origin
    @Published var ringRadius: CGFloat = 0          // normalized
    @Published var pressTip: CGPoint? = nil
    @Published var progress: Double = 0             // 0...1 hold completion
    @Published var cue: String = "Bring your hand into the frame."

    private let holdTargetSec: Double = 30
    private var holdAccum: Double = 0
    private var lastTime: TimeInterval = 0
    private var offsets: [CGPoint] = []             // recent target-relative offsets

    var color: Color {
        switch phase {
        case .holding, .complete:        return Ink.good
        case .wrongFace, .paused:        return Ink.warn
        case .onTargetUnstable:          return Ink.warn
        case .searching, .noHand:        return Ink.hint
        }
    }

    func reset() { holdAccum = 0; offsets = []; progress = 0; phase = .noHand }

    func update(hands: [Hand], point: Acupoint, now: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(now - lastTime, 0.1)
        lastTime = now
        guard let target = point.mediapipeTarget else { phase = .searching; return }

        if hands.isEmpty {
            phase = .noHand; cue = "Bring your hand into the frame."
            ringCenter = nil; pressTip = nil; offsets = []
            return
        }

        // Pick the RECEIVER = the hand whose target zone is closest to the other's press tip.
        let receiver: Hand, presser: Hand?
        if hands.count >= 2 {
            let a = hands[0], b = hands[1]
            func d(_ recv: Hand, _ other: Hand) -> CGFloat {
                guard let t = recv.weightedTarget(target.anchors),
                      let tip = other.p(target.pressFinger) else { return .greatestFiniteMagnitude }
                return dist(t, tip)
            }
            if d(b, a) < d(a, b) { receiver = b; presser = a } else { receiver = a; presser = b }
        } else {
            receiver = hands[0]; presser = nil
        }

        // Face gate on the receiving hand.
        let faceOK = point.requiresDorsal ? receiver.isDorsal : !receiver.isDorsal
        if !faceOK {
            phase = .wrongFace
            cue = point.requiresDorsal ? "Turn the back of your hand toward the camera."
                                       : "Turn your palm toward the camera."
            ringCenter = receiver.weightedTarget(target.anchors)
            ringRadius = target.toleranceXHandSize * receiver.handSize
            pressTip = nil; offsets = []
            return
        }

        guard let center = receiver.weightedTarget(target.anchors) else { phase = .searching; return }
        ringCenter = center
        ringRadius = target.toleranceXHandSize * receiver.handSize

        guard let presser, let tip = presser.p(target.pressFinger) else {
            phase = .searching
            cue = "Bring your pressing finger into the zone — keep both hands in view."
            pressTip = nil; offsets = []
            return
        }
        pressTip = tip

        let tol = target.toleranceXHandSize * receiver.handSize
        let onTarget = dist(tip, center) < tol

        // Steadiness: variance of recent offsets below a threshold.
        offsets.append(CGPoint(x: tip.x - center.x, y: tip.y - center.y))
        if offsets.count > 15 { offsets.removeFirst(offsets.count - 15) }
        let stable = offsets.count >= 5 && offsetVariance(offsets) < 0.06 * receiver.handSize

        if onTarget && stable {
            phase = .holding
            holdAccum += dt
            cue = point.coachHold
        } else if onTarget {
            phase = .onTargetUnstable
            cue = "Hold it steady."
        } else {
            phase = holdAccum > 0 ? .paused : .searching
            cue = point.coachAlign
        }

        progress = min(1, holdAccum / holdTargetSec)
        if progress >= 1 { phase = .complete; cue = "Done — nicely held." }
    }

    private func offsetVariance(_ pts: [CGPoint]) -> CGFloat {
        func std(_ v: [CGFloat]) -> CGFloat {
            let m = v.reduce(0, +) / CGFloat(v.count)
            return sqrt(v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / CGFloat(v.count))
        }
        return max(std(pts.map(\.x)), std(pts.map(\.y)))
    }
}
