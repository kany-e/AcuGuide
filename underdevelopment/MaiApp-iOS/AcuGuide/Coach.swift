import SwiftUI

enum CoachPhase { case noHand, wrongFace, searching, onTargetUnstable, holding, paused, complete }

// ---------------------------------------------------------------------------
// Tunable constants — mirror engine.js `CONST` and useCoachingState.ts. engine.js
// is the authority for the state machine (it is what the replay fixtures validate),
// so where the web references differ we take its values.
// ---------------------------------------------------------------------------
enum CoachConst {
    static let minHoldConfirmS       = 0.07   // steady this long before the hold timer advances
    static let enterDropoutDebounceS = 0.25   // stay engaged through brief dips inside the exit band
    static let pauseGraceS           = 1.5    // == GRACE_MS: keep timer PAUSED (not reset) after leaving
    static let stabilityWindowS      = 0.2    // trailing window for the steadiness std
    static let stabilityStdThreshold = 0.06   // std of offset (in handSize units) below this = steady
    static let holdTargetS           = 30.0   // accumulated HOLDING seconds to COMPLETE
    static let exitRadiusMult        = 1.6    // exit radius = 1.6x the enter radius (hysteresis)
    static let swapConfirmFrames     = 6      // role reassignment must be "wrong" this many frames
}

// Per-frame temporal input — the native equivalent of engine.js FrameState.contact, so
// the same state machine can be driven by the live camera or by the replay fixtures.
struct CoachFrameInput {
    var t: Double                 // monotonic seconds
    var present: Bool             // usable receiving hand in frame
    var faceCorrect: Bool         // showing the surface the point sits on
    var insideEnterRadius: Bool   // press tip within the enter radius
    var insideExitRadius: Bool    // press tip within the larger exit radius
    var offsetXHandSize: Double?  // |tip - target| / handSize; nil when no pressing finger
}

// ---------------------------------------------------------------------------
// Faithful Swift port of engine.js `FeedbackStateMachine` — the validated temporal
// layer: enter/exit hysteresis, dropout debounce, pause-grace, min-hold-confirm.
// Pure and deterministic so Phase 3 can drive it frame-by-frame from the fixtures.
// ---------------------------------------------------------------------------
final class CoachStateMachine {
    var holdTargetS: Double                  // overridable (fixtures use a short target)
    init(holdTargetS: Double = CoachConst.holdTargetS) { self.holdTargetS = holdTargetS }

    private var prevT: Double? = nil
    private var engaged = false
    private var dropoutTimer = 0.0
    private var offsetWindow: [(t: Double, off: Double)] = []
    private var stableRun = 0.0
    private(set) var holdTime = 0.0
    private var lastHoldT = -Double.infinity
    private(set) var completed = false

    func reset() {
        prevT = nil; engaged = false; dropoutTimer = 0
        offsetWindow.removeAll(); stableRun = 0
        holdTime = 0; lastHoldT = -Double.infinity; completed = false
    }

    var progress: Double { min(1, holdTime / holdTargetS) }

    private func dt(_ t: Double) -> Double {
        defer { prevT = t }
        if let p = prevT, t - p > 0 { return t - p }
        return 1.0 / 30.0   // first frame / duplicate timestamp (engine.js uses 1/fps)
    }

    func step(_ f: CoachFrameInput) -> CoachPhase {
        let d = dt(f.t)

        if completed { return .complete }
        if !f.present { resetTracking(); return .noHand }
        if !f.faceCorrect { resetTracking(); return .wrongFace }

        updateEngaged(f, d)
        updateStability(f, d)
        let holdingNow = engaged && stableRun >= CoachConst.minHoldConfirmS

        var phase: CoachPhase
        if engaged {
            if holdingNow {
                phase = .holding
                holdTime += d
                lastHoldT = f.t
            } else {
                phase = .onTargetUnstable
            }
        } else if holdTime > 0 && f.t - lastHoldT <= CoachConst.pauseGraceS {
            phase = .paused
        } else {
            phase = .searching
        }

        if holdTime >= holdTargetS { completed = true; phase = .complete }
        return phase
    }

    private func updateEngaged(_ f: CoachFrameInput, _ d: Double) {
        if f.insideEnterRadius {
            engaged = true; dropoutTimer = 0
        } else if !f.insideExitRadius {
            engaged = false; dropoutTimer = 0
        } else {
            // inside the exit band but outside the enter radius: hold engagement briefly
            dropoutTimer += d
            if dropoutTimer >= CoachConst.enterDropoutDebounceS { engaged = false }
        }
    }

    private func updateStability(_ f: CoachFrameInput, _ d: Double) {
        if let off = f.offsetXHandSize {
            offsetWindow.append((f.t, off))
            let cutoff = f.t - CoachConst.stabilityWindowS
            while let first = offsetWindow.first, first.t < cutoff { offsetWindow.removeFirst() }
        }
        let steady = engaged && offsetWindow.count >= 2 &&
            std(offsetWindow.map { $0.off }) < CoachConst.stabilityStdThreshold
        stableRun = steady ? stableRun + d : 0
    }

    private func resetTracking() {
        engaged = false; dropoutTimer = 0
        offsetWindow.removeAll(); stableRun = 0
        // holdTime / lastHoldT persist — PAUSE_GRACE governs re-entry, exactly as engine.js.
    }

    private func std(_ values: [Double]) -> Double {
        let n = values.count
        if n < 2 { return 0 }
        let mean = values.reduce(0, +) / Double(n)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)
        return variance.squareRoot()
    }
}

// ---------------------------------------------------------------------------
// CoachEngine — the geometry + presentation layer that drives CoachStateMachine.
// Native equivalent of usePressDetection (One-Euro target smoothing, role/contact)
// feeding useCoachingState. Publishes everything the AR overlay renders.
// ---------------------------------------------------------------------------
final class CoachEngine: ObservableObject {
    @Published var phase: CoachPhase = .noHand
    @Published var ringCenter: CGPoint? = nil      // normalized, top-left origin (smoothed)
    @Published var ringRadius: CGFloat = 0          // normalized
    @Published var pressTip: CGPoint? = nil
    @Published var progress: Double = 0             // 0...1 hold completion
    @Published var cue: String = "Bring your hand into the frame."

    private let machine = CoachStateMachine()
    private let smoother = OneEuroPoint()

    // Sticky two-hand role tracking (stops the ring jumping between hands).
    private var lastReceiverWrist: CGPoint? = nil
    private var lastPresserWrist: CGPoint? = nil
    private var swapVotes = 0

    var color: Color {
        switch phase {
        case .holding, .complete:   return Ink.good
        case .wrongFace, .paused:   return Ink.warn
        case .onTargetUnstable:     return Ink.warn
        case .searching, .noHand:   return Ink.hint
        }
    }

    func reset() {
        machine.reset(); smoother.reset(); roleReset()
        phase = .noHand; ringCenter = nil; pressTip = nil; progress = 0
        cue = "Bring your hand into the frame."
    }

    func update(hands: [Hand], point: Acupoint, now: TimeInterval) {
        guard let target = point.mediapipeTarget else {
            // Atlas-only point — never AR-coached. Defensive: should not be reachable.
            phase = .searching; ringCenter = nil; pressTip = nil; return
        }

        // 1) No usable hand.
        guard !hands.isEmpty else {
            smoother.reset(); roleReset(); ringCenter = nil; pressTip = nil
            apply(machine.step(noHandInput(now)), point: point, hasPresser: false)
            return
        }

        // 2) Assign receiver / presser with stickiness.
        let (receiver, presser) = assignRoles(hands, target: target)

        // 3) Geometry. If we can't trust the target geometry, treat as no usable hand.
        guard let rawCenter = receiver.weightedTarget(target.anchors),
              receiver.handSize > 0 else {
            smoother.reset(); ringCenter = nil; pressTip = nil
            apply(machine.step(noHandInput(now)), point: point, hasPresser: false)
            return
        }
        let hs = receiver.handSize
        let center = smoother.filter(rawCenter, now)   // One-Euro BEFORE hit-test + draw
        let tol = target.toleranceXHandSize * hs
        ringCenter = center
        ringRadius = tol

        // 4) Press tip + contact (raw landmark for the tip).
        let faceCorrect = point.requiresDorsal ? receiver.isDorsal : !receiver.isDorsal
        var inEnter = false, inExit = false, hasPresser = false
        var offN: Double? = nil
        if let presser, let tip = presser.p(target.pressFinger) {
            pressTip = tip; hasPresser = true
            let dd = dist(tip, center)
            inEnter = dd < tol
            inExit = dd < tol * CoachConst.exitRadiusMult
            offN = Double(dd / hs)
        } else {
            pressTip = nil
        }

        let result = machine.step(CoachFrameInput(
            t: now, present: true, faceCorrect: faceCorrect,
            insideEnterRadius: inEnter, insideExitRadius: inExit, offsetXHandSize: offN))

        if result == .wrongFace { pressTip = nil }   // ring stays to guide the flip
        apply(result, point: point, hasPresser: hasPresser)
    }

    private func noHandInput(_ now: TimeInterval) -> CoachFrameInput {
        CoachFrameInput(t: now, present: false, faceCorrect: false,
                        insideEnterRadius: false, insideExitRadius: false, offsetXHandSize: nil)
    }

    private func apply(_ phase: CoachPhase, point: Acupoint, hasPresser: Bool) {
        self.phase = phase
        progress = machine.progress
        cue = cueFor(phase, point: point, hasPresser: hasPresser)
    }

    private func cueFor(_ phase: CoachPhase, point: Acupoint, hasPresser: Bool) -> String {
        switch phase {
        case .noHand:           return "Bring your hand into the frame."
        case .wrongFace:        return point.requiresDorsal
                                    ? "Turn the back of your hand toward the camera."
                                    : "Turn your palm toward the camera."
        case .searching:        return hasPresser ? point.coachAlign
                                    : "Bring your pressing finger into the zone — keep both hands in view."
        case .onTargetUnstable: return "Hold it steady."
        case .holding:          return point.coachHold
        case .paused:           return point.coachAlign
        case .complete:         return "Done — nicely held."
        }
    }

    // MARK: - Sticky role assignment

    private func roleReset() { lastReceiverWrist = nil; lastPresserWrist = nil; swapVotes = 0 }

    private func assignRoles(_ hands: [Hand], target: MediaPipeTarget) -> (Hand, Hand?) {
        guard hands.count >= 2 else { roleReset(); return (hands[0], nil) }
        let a = hands[0], b = hands[1]

        // Heuristic preference: receiver = the hand whose target zone is nearest the
        // OTHER hand's press tip (the original choice — preserved as the initial pick).
        func score(_ recv: Hand, _ other: Hand) -> CGFloat {
            guard let t = recv.weightedTarget(target.anchors),
                  let tip = other.p(target.pressFinger) else { return .greatestFiniteMagnitude }
            return dist(t, tip)
        }
        let prefAIsReceiver = score(a, b) <= score(b, a)

        // Match the two current hands to the previous roles by wrist proximity (Vision
        // does not give stable IDs across frames), then only flip on sustained disagreement.
        if let lrw = lastReceiverWrist, let lpw = lastPresserWrist,
           let aw = a.p(.wrist), let bw = b.p(.wrist) {
            let cost1 = dist(aw, lrw) + dist(bw, lpw)   // a=receiver, b=presser
            let cost2 = dist(bw, lrw) + dist(aw, lpw)   // b=receiver, a=presser
            let stickyAIsReceiver = cost1 <= cost2

            if prefAIsReceiver == stickyAIsReceiver { swapVotes = 0 } else { swapVotes += 1 }

            var aIsReceiver = stickyAIsReceiver
            if swapVotes >= CoachConst.swapConfirmFrames {
                aIsReceiver = prefAIsReceiver
                swapVotes = 0
                smoother.reset()   // ring jumps to the new hand — don't lerp across the gap
            }
            return commitRoles(aIsReceiver: aIsReceiver, a: a, b: b)
        }

        return commitRoles(aIsReceiver: prefAIsReceiver, a: a, b: b)
    }

    private func commitRoles(aIsReceiver: Bool, a: Hand, b: Hand) -> (Hand, Hand?) {
        let receiver = aIsReceiver ? a : b
        let presser  = aIsReceiver ? b : a
        lastReceiverWrist = receiver.p(.wrist)
        lastPresserWrist  = presser.p(.wrist)
        return (receiver, presser)
    }
}
