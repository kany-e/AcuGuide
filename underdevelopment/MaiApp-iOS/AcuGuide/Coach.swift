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
    static let minConfidence         = 0.5    // == engine.js MIN_CONFIDENCE: usable-hand gate
    // Live-path safeguard beyond engine.js: the recorded fixtures have steady ~33ms deltas, but
    // a camera stall / app backgrounding can produce a multi-second gap. Clamp dt so a single
    // jumbo frame can't credit seconds of hold/steadiness at once (matches the old min(_,0.1)).
    static let maxFrameDtS           = 0.1
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
        if let p = prevT, t - p > 0 { return min(t - p, CoachConst.maxFrameDtS) }
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
                // Credit hold / refresh the grace anchor ONLY on a frame with a real offset
                // measurement. The occlusion path keeps engagement alive (dropout debounce) while
                // stepping with offset nil; it must not advance the timer on unverifiable geometry.
                if f.offsetXHandSize != nil {
                    holdTime += d
                    lastHoldT = f.t
                }
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
        }
        // Age out stale samples EVERY frame (even one with no offset), so a sustained occlusion
        // drops steadiness instead of looking steady on samples from before the dropout.
        let cutoff = f.t - CoachConst.stabilityWindowS
        while let first = offsetWindow.first, first.t < cutoff { offsetWindow.removeFirst() }
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
    private let smoother = OneEuroPoint()        // target ring
    private let pressSmoother = OneEuroPoint()   // second-hand press tip (Vision is noisy on it)

    // Sticky two-hand role tracking (stops the ring jumping between hands).
    private var lastReceiverWrist: CGPoint? = nil
    private var lastPresserWrist: CGPoint? = nil
    private var swapVotes = 0

    // Last face verdict that we could actually compute — reused when a frame can't verify the
    // face (a required MCP landmark dropped) so a brief occlusion doesn't flip to WRONG_FACE
    // and reset the steadiness run.
    private var lastFaceCorrect = false

    // Reset the target smoother (called on a confirmed role swap or a mirror flip — both are
    // coordinate discontinuities that would otherwise spike the One-Euro velocity estimate).
    func smootherReset() { smoother.reset(); pressSmoother.reset() }

    var color: Color {
        switch phase {
        case .holding, .complete:   return Ink.good
        case .wrongFace, .paused:   return Ink.warn
        case .onTargetUnstable:     return Ink.warn
        case .searching, .noHand:   return Ink.hint
        }
    }

    func reset() {
        machine.reset(); smoother.reset(); pressSmoother.reset(); roleReset()
        lastFaceCorrect = false
        phase = .noHand; ringCenter = nil; pressTip = nil; progress = 0
        cue = AppLocale.pick("把手放进画面。", "Bring your hand into the frame.")
    }

    func update(hands: [Hand], point: Acupoint, now: TimeInterval) {
        guard let target = point.mediapipeTarget else {
            // Atlas-only point — never AR-coached. Defensive: should not be reachable.
            phase = .searching; ringCenter = nil; pressTip = nil; return
        }

        // 1) No usable hand.
        guard !hands.isEmpty else {
            smoother.reset(); pressSmoother.reset(); roleReset(); lastFaceCorrect = false
            ringCenter = nil; pressTip = nil
            apply(machine.step(noHandInput(now)), point: point, hasPresser: false)
            return
        }

        // 2) Assign receiver / presser with stickiness.
        let (receiver, presser) = assignRoles(hands, target: target)

        // 3) Geometry. The receiving hand IS present but a target anchor may be momentarily
        // unresolvable (e.g. the pressing finger occludes the ring/pinky knuckles — the exact
        // case smoothing exists for). Treat that as present-but-no-contact so a brief occlusion
        // PAUSES within grace (via the dropout debounce) instead of flashing NO_HAND and wiping
        // the steadiness run. Keep the last ring; drop the now-stale press tip. Do NOT reset the
        // smoother — geometry resumes continuously.
        guard let rawCenter = receiver.weightedTarget(target.anchors),
              receiver.handSize > 0 else {
            pressTip = nil
            let result = machine.step(CoachFrameInput(
                t: now, present: true, faceCorrect: true,
                insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: nil))
            apply(result, point: point, hasPresser: false)
            return
        }
        let hs = receiver.handSize
        let center = smoother.filter(rawCenter, now)   // One-Euro BEFORE hit-test + draw
        let tol = target.toleranceXHandSize * hs
        ringCenter = center
        ringRadius = tol

        // 4) Face gate. isDorsal is nil when a required MCP landmark is missing; in that case
        // reuse the last verdict we could compute so a transient drop doesn't flip to WRONG_FACE.
        let faceCorrect: Bool
        if let dorsal = receiver.isDorsal {
            faceCorrect = point.requiresDorsal ? dorsal : !dorsal
            lastFaceCorrect = faceCorrect
        } else {
            faceCorrect = lastFaceCorrect
        }

        // 5) Press tip + contact. The second (massaging) hand's fingertip is noisy in Vision, so
        // One-Euro-smooth it BEFORE the contact test and before drawing (mirrors the target ring).
        var inEnter = false, inExit = false, hasPresser = false
        var offN: Double? = nil
        if let presser, let rawTip = presser.p(target.pressFinger) {
            let tip = pressSmoother.filter(rawTip, now)
            pressTip = tip; hasPresser = true
            let dd = dist(tip, center)
            inEnter = dd < tol
            inExit = dd < tol * CoachConst.exitRadiusMult
            offN = Double(dd / hs)
        } else {
            pressTip = nil; pressSmoother.reset()   // presser dropped — restart the filter clean
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
        case .noHand:           return AppLocale.pick("把手放进画面。", "Bring your hand into the frame.")
        case .wrongFace:        return point.requiresDorsal
                                    ? AppLocale.pick("把手背朝向相机。", "Turn the back of your hand toward the camera.")
                                    : AppLocale.pick("把手掌朝向相机。", "Turn your palm toward the camera.")
        case .searching:        return hasPresser ? point.coachAlignL
                                    : AppLocale.pick("把按压的手指移入区域 — 双手都保持在画面中。",
                                                     "Bring your pressing finger into the zone — keep both hands in view.")
        case .onTargetUnstable: return AppLocale.pick("保持稳定。", "Hold it steady.")
        case .holding:          return point.coachHoldL
        case .paused:           return point.coachAlignL
        case .complete:         return AppLocale.pick("完成 — 保持得很好。", "Done — nicely held.")
        }
    }

    // MARK: - Sticky role assignment

    private func roleReset() { lastReceiverWrist = nil; lastPresserWrist = nil; swapVotes = 0 }

    private func assignRoles(_ hands: [Hand], target: MediaPipeTarget) -> (Hand, Hand?) {
        // One hand: keep the sticky receiver/presser wrist anchors (a brief drop to one hand —
        // reaching, repositioning — should NOT discard the identity hysteresis; cleared only when
        // NO hands are present, via roleReset in update). But DO reset swapVotes: the one-hand gap
        // breaks the "consecutive disagreement" streak, so a partial count must not carry over and
        // trigger an early/spurious swap when the second hand returns.
        guard hands.count >= 2 else { swapVotes = 0; return (hands[0], nil) }
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
                // Both roles flip to physically different hands — reset BOTH filters so neither the
                // ring nor the press tip lerps across the discontinuity.
                smoother.reset(); pressSmoother.reset()
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
