import SwiftUI

enum CoachPhase { case noHand, wrongFace, searching, onTargetUnstable, holding, resting, paused, complete }

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
    // Session shape: repeated press/release ROUNDS, not one long hold — matching published self-care
    // guidance (30s–3min per point in repeated bouts with releases; MSK's P6 handout uses 2–3min of
    // circular pressure, general handouts 30s–2min, interval protocols press ~10s / release ~5s for
    // 1–3min) and this app's own FAQ ("30–60 seconds per point … repeat after a short rest").
    // 4 × 30s ≈ 2 minutes of press — mid-range. The user can END the session at any round; the recap
    // reports rounds/seconds honestly (quitting early is normal, not failure).
    static let holdTargetS           = 30.0   // accumulated HOLDING seconds to complete ONE round
    static let restS                 = 10.0   // release-and-breathe gap between rounds
    static let sessionRounds         = 4      // rounds per coached session
    static let exitRadiusMult        = 1.6    // exit radius = 1.6x the enter radius (hysteresis)
    static let swapConfirmFrames     = 6      // role reassignment must be "wrong" this many frames
    static let minConfidence         = 0.5    // == engine.js MIN_CONFIDENCE: usable-hand gate
    // Live-path safeguard beyond engine.js: the recorded fixtures have steady ~33ms deltas, but
    // a camera stall / app backgrounding can produce a multi-second gap. Clamp dt so a single
    // jumbo frame can't credit seconds of hold/steadiness at once (matches the old min(_,0.1)).
    static let maxFrameDtS           = 0.1
    // The massaging fingertip is the joint Vision drops most (it's the one doing the occluding —
    // confirmed unstable in on-device shadow capture). Keep the press dot + engagement alive through
    // a dropout this brief (the state machine's dropout debounce then governs), instead of instantly
    // nil-ing the tip / resetting its smoother / disengaging on a single missed frame.
    static let tipGraceS             = 0.3
    // How long a lone surviving hand may be treated as "the presser occluding the receiver" before
    // the assumption decays and roles reset (the hand becomes the receiver by the single-hand rule).
    // Unbounded, this state froze the ring forever and could self-latch a receiving hand as presser.
    static let lonePresserGraceS     = 1.5
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
    @Published var progress: Double = 0             // 0...1 hold completion of the CURRENT round
    @Published var cue: String = "Bring your hand into the frame."

    // Session layer: repeated press/release rounds on top of the validated per-round state machine
    // (the machine itself stays a pure single-hold automaton — fixtures still validate it).
    @Published private(set) var roundsDone = 0
    @Published private(set) var sessionComplete = false
    let roundsTarget: Int
    private let restS: Double
    private var restUntil: Double? = nil            // non-nil while in the release gap
    private var restRemaining = 0                   // whole seconds, for the rest cue
    private var heldAccum = 0.0                     // banked hold seconds from finished rounds
    var totalHeldS: Double { heldAccum + machine.holdTime }   // for the recap (quit-anytime honest)
    private(set) var roundTimes: [Double] = []      // hold seconds per COMPLETED round (recap breakdown)

    // Secondary "why is nothing happening" line under the main cue — set only when the receiving
    // hand's geometry has been unresolvable for a while (occlusion), so it never flashes on the
    // routine one-frame dropouts the grace timers already absorb.
    @Published private(set) var hintText: String? = nil
    private var anchorLostSince: Double? = nil

    private let machine: CoachStateMachine

    init(roundsTarget: Int = CoachConst.sessionRounds,
         roundHoldS: Double = CoachConst.holdTargetS,
         restS: Double = CoachConst.restS) {
        self.roundsTarget = roundsTarget
        self.restS = restS
        self.machine = CoachStateMachine(holdTargetS: roundHoldS)
    }
    private let smoother = OneEuroPoint()        // target ring
    // Second-hand press tip. Tuned heavier than the target ring: minCutoff 0.6 (more smoothing at
    // rest — the tip should sit still while pressing) and beta 0.8 (noise spikes read as "speed"
    // and would otherwise disable smoothing exactly when the occluded tip wanders; user-reported drift).
    private let pressSmoother = OneEuroPoint(OneEuroOptions(minCutoff: 0.6, beta: 0.8, dCutoff: 1.0))

    // Sticky two-hand role tracking (stops the ring jumping between hands).
    private var lastReceiverWrist: CGPoint? = nil
    private var lastPresserWrist: CGPoint? = nil
    private var swapVotes = 0

    // Last face verdict that we could actually compute — reused when a frame can't verify the
    // face (a required MCP landmark dropped) so a brief occlusion doesn't flip to WRONG_FACE
    // and reset the steadiness run.
    private var lastFaceCorrect = false

    // When the press tip was last actually measured — drives the tipGraceS dropout grace.
    private var lastTipT = -Double.infinity

    // When the lone-presser (receiver occluded) state began — bounds it to lonePresserGraceS.
    private var lonePresserSince: Double? = nil

    // A camera flip is a NEW SCENE in a different coordinate parity: drop everything keyed to the
    // old one — smoothers, sticky role anchors, the face verdict, the lone-presser assumption, and
    // the on-screen ring/tip (their positions are meaningless in the new frame).
    func cameraFlipped() {
        smootherReset(); roleReset()
        lastFaceCorrect = false; lonePresserSince = nil
        ringCenter = nil; pressTip = nil
    }

    // Reset the target smoother (called on a confirmed role swap or a mirror flip — both are
    // coordinate discontinuities that would otherwise spike the One-Euro velocity estimate).
    // The tip grace drops too: a pre-flip tip is in the wrong coordinate space.
    func smootherReset() { smoother.reset(); pressSmoother.reset(); lastTipT = -.infinity }

    var color: Color {
        switch phase {
        case .holding, .complete, .resting: return Ink.good
        case .wrongFace, .paused:           return Ink.warn
        case .onTargetUnstable:             return Ink.warn
        case .searching, .noHand:           return Ink.hint
        }
    }

    func reset() {
        machine.reset(); smoother.reset(); pressSmoother.reset(); roleReset()
        lastFaceCorrect = false; lastTipT = -.infinity; lonePresserSince = nil
        roundsDone = 0; sessionComplete = false; restUntil = nil; heldAccum = 0
        roundTimes = []; clearHint()
        phase = .noHand; ringCenter = nil; pressTip = nil; progress = 0
        cue = AppLocale.pick("把手放进画面。", "Bring your hand into the frame.")
    }

    // Occlusion-hint bookkeeping. The 1-second delay keeps it quiet through the transient dropouts
    // the grace timers already smooth over; the equality guards keep @Published writes to changes.
    private func occlusionHint(_ now: TimeInterval, _ text: String) {
        let since = anchorLostSince ?? now
        anchorLostSince = since
        if now - since > 1.0, hintText != text { hintText = text }
    }
    private func clearHint() {
        anchorLostSince = nil
        if hintText != nil { hintText = nil }
    }

    func update(hands: [Hand], point: Acupoint, now: TimeInterval) {
        guard let target = point.mediapipeTarget else {
            // Atlas-only point — never AR-coached. Defensive: should not be reachable.
            phase = .searching; ringCenter = nil; pressTip = nil; return
        }

        // Release gap between rounds — timer-driven, NOT machine-driven: the user is told to let go,
        // so hands leaving the frame is expected and must not flash NO_HAND. The last ring stays on
        // screen (dim) as the guide back; the round machine restarts clean when the gap ends.
        if let until = restUntil {
            if now < until {
                restRemaining = Int((until - now).rounded(.up))
                pressTip = nil
                clearHint()
                apply(.resting, point: point, hasPresser: false)
                return
            }
            restUntil = nil                                            // machine was reset when the gap began
            smoother.reset(); pressSmoother.reset(); lastTipT = -.infinity
        }

        // 1) No usable hand.
        guard !hands.isEmpty else {
            smoother.reset(); pressSmoother.reset(); roleReset(); lastFaceCorrect = false
            lastTipT = -.infinity; lonePresserSince = nil
            ringCenter = nil; pressTip = nil
            clearHint()   // the NO_HAND cue already says what to do
            apply(machine.step(noHandInput(now)), point: point, hasPresser: false)
            return
        }

        // 2) Assign receiver / presser with stickiness. A nil receiver means only the MASSAGING hand
        // survived detection (it sits on top mid-press and occludes the receiver) — keep the last
        // ring and step as present-but-unverifiable, exactly like the anchor-occlusion path, so
        // PAUSE-grace governs instead of the ring snapping onto the massaging hand.
        // The assumption is TIME-BOUNDED (lonePresserGraceS): if the "occluded receiver" never
        // returns, roles reset and the surviving hand becomes the receiver by the single-hand rule
        // — otherwise this state froze the stale ring forever and, because the presser anchor used
        // to track the lone hand, could permanently misclassify a receiving hand as the presser.
        // Weak-tier hands (whole-hand confidence 0.3–0.5 — typically the foreshortened massaging
        // hand) may ONLY press: role assignment sees strong hands, and a weak hand fills the
        // presser slot afterwards. A weak hand must never anchor the ring, and weak-only frames
        // decay to "no usable hand" rather than promoting one to receiver.
        let strongHands = hands.filter { !$0.weak }
        var receiverOpt: Hand?
        var presser: Hand?
        if strongHands.isEmpty {
            (receiverOpt, presser) = (nil, hands.first)
        } else {
            (receiverOpt, presser) = assignRoles(strongHands, target: target)
            if presser == nil, receiverOpt != nil { presser = hands.first(where: { $0.weak }) }
        }
        if receiverOpt == nil {
            let since = lonePresserSince ?? now
            lonePresserSince = since
            if now - since > CoachConst.lonePresserGraceS {
                if strongHands.isEmpty {
                    // Only weak hands remain past the grace: nothing here can hold the ring.
                    // Read as "no usable receiving hand" (keep `lonePresserSince` stale so this
                    // doesn't re-arm a fresh grace every frame while weak-only persists).
                    smoother.reset(); pressSmoother.reset(); roleReset(); lastFaceCorrect = false
                    lastTipT = -.infinity
                    ringCenter = nil; pressTip = nil
                    apply(machine.step(noHandInput(now)), point: point, hasPresser: false)
                    return
                }
                roleReset(); lonePresserSince = nil
                (receiverOpt, presser) = assignRoles(strongHands, target: target)   // lone strong hand = receiver
            }
        } else {
            lonePresserSince = nil
        }
        guard let receiver = receiverOpt else {
            // Same tip handling as the main path: measured → smooth + draw; brief dropout → keep
            // the dot within tipGraceS; expired → clear + reset the filter so a re-acquired tip
            // doesn't lerp across the screen with stale velocity.
            if let presser, let tip = presser.pressTip(target.pressFinger) {
                pressTip = pressSmoother.filter(tip.point, now); lastTipT = now
            } else if pressTip != nil, now - lastTipT <= CoachConst.tipGraceS {
                // keep the last dot
            } else {
                pressTip = nil; pressSmoother.reset()
            }
            // The receiving hand has been occluded past the transient window — say so, plainly.
            occlusionHint(now, AppLocale.pick("让接受按压的那只手完整回到画面中。",
                                              "Keep the hand being pressed fully in view."))
            let result = machine.step(CoachFrameInput(
                t: now, present: true, faceCorrect: true,
                insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: nil))
            apply(result, point: point, hasPresser: presser != nil)
            return
        }

        // 3) Geometry. The receiving hand IS present but a target anchor may be momentarily
        // unresolvable (e.g. the pressing finger occludes the ring/pinky knuckles — the exact
        // case smoothing exists for). Treat that as present-but-no-contact so a brief occlusion
        // PAUSES within grace (via the dropout debounce) instead of flashing NO_HAND and wiping
        // the steadiness run. Keep the last ring; drop the now-stale press tip. Do NOT reset the
        // smoother — geometry resumes continuously.
        guard let rawCenter = receiver.weightedTarget(target.anchors),
              receiver.handSize > 0 else {
            pressTip = nil
            // Sustained anchor loss = the pressing hand is covering the receiver's landmarks.
            occlusionHint(now, AppLocale.pick("保持受压手的手腕和指节可见。",
                                              "Keep the wrist and knuckles of the receiving hand visible."))
            let result = machine.step(CoachFrameInput(
                t: now, present: true, faceCorrect: true,
                insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: nil))
            apply(result, point: point, hasPresser: false)
            return
        }
        clearHint()   // geometry is resolving again
        let hs = receiver.handSize
        // M1 shadow mode: run the learned CoreML head next to the affine target + log the delta. Never
        // alters the ring/state machine — reads the hand only. See LearnedLocalizer / M1 experiment.
        ShadowLocalizer.shared.record(hand: receiver, point: point, affine: rawCenter, handSize: hs, pressing: presser != nil)
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
        // The tip is also the joint Vision DROPS most (it's doing the occluding), so a transient
        // loss gets a short grace (tipGraceS): keep the last dot on screen and step the machine as
        // inside-the-exit-band with NO offset — engagement survives via the dropout debounce, but
        // hold time never advances on unverifiable geometry (same rule as receiver occlusion).
        // Only after the grace expires does the tip clear + the filter reset (a longer gap means
        // the finger really left; restarting the filter clean avoids a stale-velocity lerp back).
        var inEnter = false, inExit = false, hasPresser = false
        var offN: Double? = nil
        if let presser, let measured = presser.pressTip(target.pressFinger) {
            let tip = pressSmoother.filter(measured.point, now)
            pressTip = tip; hasPresser = true
            lastTipT = now
            let dd = dist(tip, center)
            // Palm-glaze gate (user-reported: "whatever hand part glazes over the area, it tracks"):
            // when a palm covers the target, Vision still hallucinates a LOW-confidence tip under it,
            // which used to start engagement. A NEW engagement now needs a confident tip; an ongoing
            // hold doesn't (mid-press confidence dips must not break HOLDING — hysteresis as usual).
            // The confidence comes from the pressTip MEASUREMENT itself, so the DIP/PIP-reconstructed
            // tip (confidence 0 — an unmeasured guess) can sustain but never start an engagement.
            // Fixture/test hands carry no confidences → default reliable, so the validated paths hold.
            let wasEngaged = phase == .holding || phase == .onTargetUnstable
            inEnter = dd < tol && (measured.confidence >= 0.4 || wasEngaged)
            inExit = dd < tol * CoachConst.exitRadiusMult
            offN = Double(dd / hs)
        } else if pressTip != nil, now - lastTipT <= CoachConst.tipGraceS {
            hasPresser = true                       // brief dropout: keep the dot + cue steady
            inExit = true                           // stay in the exit band → debounce governs
        } else {
            pressTip = nil; pressSmoother.reset()   // presser really gone — restart the filter clean
        }

        let result = machine.step(CoachFrameInput(
            t: now, present: true, faceCorrect: faceCorrect,
            insideEnterRadius: inEnter, insideExitRadius: inExit, offsetXHandSize: offN))

        // Round finished: bank its hold seconds, then either the whole SESSION is done or the
        // release-and-breathe gap starts. (Only this fully-measured path can newly complete a
        // round — the occlusion paths step with no offset, which never advances the hold.)
        if result == .complete && !sessionComplete {
            roundsDone += 1
            roundTimes.append(machine.holdTime)   // this round's hold, for the recap breakdown
            if roundsDone >= roundsTarget {
                sessionComplete = true      // machine stays latched; totalHeldS still reads its holdTime
            } else {
                // Bank the round's hold and reset the machine NOW (it is never stepped during the
                // gap), so totalHeldS = banked + live never double-counts a finished round.
                heldAccum += machine.holdTime
                machine.reset()
                restUntil = now + restS
                restRemaining = Int(restS.rounded(.up))
                pressTip = nil
                apply(.resting, point: point, hasPresser: false)
                return
            }
        }

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
        case .wrongFace:        return faceCue(point)
        case .searching:        return hasPresser ? alignCue(point)
                                    : AppLocale.pick("把按压的手指移入区域 — 双手都保持在画面中。",
                                                     "Bring your pressing finger into the zone — keep both hands in view.")
        case .onTargetUnstable: return AppLocale.pick("保持稳定。", "Hold it steady.")
        case .holding:          return holdCue(point)
        case .resting:          return AppLocale.pick(
                                    "很好 — 松开手指，缓慢呼吸。\(restRemaining) 秒后开始第 \(min(roundsDone + 1, roundsTarget))/\(roundsTarget) 轮。",
                                    "Nice — release and breathe. Round \(min(roundsDone + 1, roundsTarget)) of \(roundsTarget) starts in \(restRemaining)s.")
        case .paused:           return alignCue(point)
        case .complete:         return AppLocale.pick("完成 — 保持得很好。", "Done — nicely held.")
        }
    }

    // PC6/SJ5 sit on the FOREARM (extrapolated past the wrist), so their cues talk about the forearm,
    // not the hand — the plain "back of your hand" prompt reads wrong there.
    private func isForearm(_ p: Acupoint) -> Bool { p.id == "PC6" || p.id == "SJ5" }

    private func faceCue(_ p: Acupoint) -> String {
        if isForearm(p) {
            return p.requiresDorsal
                ? AppLocale.pick("把前臂外侧（手背那一侧）转向相机。",
                                 "Turn the outer side of your forearm — the back-of-hand side — toward the camera.")
                : AppLocale.pick("手掌向上，让前臂内侧朝向相机。",
                                 "Turn your palm up so the inner side of your forearm faces the camera.")
        }
        return p.requiresDorsal
            ? AppLocale.pick("把手背朝向相机。", "Turn the back of your hand toward the camera.")
            : AppLocale.pick("把手掌朝向相机。", "Turn your palm toward the camera.")
    }

    // Per-point cues where authored (TE3), otherwise a generic cue keyed to the surface — so every
    // coachable point gives a meaningful align/hold prompt.
    private func alignCue(_ p: Acupoint) -> String {
        if !p.coachAlignL.isEmpty { return p.coachAlignL }
        if isForearm(p) {
            return p.requiresDorsal
                ? AppLocale.pick("前臂放稳，腕横纹上约两指宽处，把指尖对准圆圈。",
                                 "Rest your forearm steady — about two finger-widths above the wrist crease — and line your fingertip up with the ring.")
                : AppLocale.pick("掌心向上、前臂放稳，腕横纹上约两指宽处，把指尖对准圆圈。",
                                 "Palm up and forearm steady — about two finger-widths above the wrist crease — line your fingertip up with the ring.")
        }
        return p.requiresDorsal
            ? AppLocale.pick("手背朝向相机，把指尖对准圆圈。", "Back of the hand to the camera — line your fingertip up with the ring.")
            : AppLocale.pick("手掌朝向相机，把指尖对准圆圈。", "Palm to the camera — line your fingertip up with the ring.")
    }
    private func holdCue(_ p: Acupoint) -> String {
        if !p.coachHoldL.isEmpty { return p.coachHoldL }
        return AppLocale.pick("很好 — 稳定用力，配合缓慢呼吸，可做小幅轻柔画圈。",
                              "Good — firm, steady pressure with slow breathing, small gentle circles.")
    }

    // MARK: - Sticky role assignment

    private func roleReset() { lastReceiverWrist = nil; lastPresserWrist = nil; swapVotes = 0 }

    private func assignRoles(_ hands: [Hand], target: MediaPipeTarget) -> (Hand?, Hand?) {
        // One hand: keep the sticky receiver/presser wrist anchors (a brief drop to one hand —
        // reaching, repositioning — should NOT discard the identity hysteresis; cleared only when
        // NO hands are present, via roleReset in update). But DO reset swapVotes: the one-hand gap
        // breaks the "consecutive disagreement" streak, so a partial count must not carry over and
        // trigger an early/spurious swap when the second hand returns.
        guard hands.count >= 2 else {
            swapVotes = 0
            let h = hands[0]
            // Identify WHICH hand survived by wrist proximity to the sticky anchors. Mid-press it is
            // usually the MASSAGING hand that survives detection (it sits on top and occludes the
            // receiver) — crowning it receiver snapped the ring onto the massaging hand
            // (user-reported on multiple points). A lone presser means the receiver is occluded,
            // NOT that roles changed.
            if let lrw = lastReceiverWrist, let lpw = lastPresserWrist, let w = h.p(.wrist),
               dist(w, lpw) < dist(w, lrw) {
                // Anchors stay FROZEN here: re-anchoring the presser to the lone hand every frame
                // made the classification self-latch (the anchor followed the hand wherever it
                // moved, so it could never be re-read as the receiver). The engine's
                // lonePresserGraceS bounds how long this verdict can stand anyway.
                return (nil, h)
            }
            if let w = h.p(.wrist) { lastReceiverWrist = w }
            return (h, nil)
        }
        let a = hands[0], b = hands[1]

        // Heuristic preference: receiver = the hand whose target zone is nearest the
        // OTHER hand's press tip (the original choice — preserved as the initial pick).
        func score(_ recv: Hand, _ other: Hand) -> CGFloat {
            guard let t = recv.weightedTarget(target.anchors),
                  let tip = other.pressTip(target.pressFinger)?.point else { return .greatestFiniteMagnitude }
            return dist(t, tip)
        }
        let sA = score(a, b), sB = score(b, a)
        let prefAIsReceiver = sA <= sB

        // Match the two current hands to the previous roles by wrist proximity (Vision
        // does not give stable IDs across frames), then only flip on sustained disagreement.
        if let lrw = lastReceiverWrist, let lpw = lastPresserWrist,
           let aw = a.p(.wrist), let bw = b.p(.wrist) {
            let cost1 = dist(aw, lrw) + dist(bw, lpw)   // a=receiver, b=presser
            let cost2 = dist(bw, lrw) + dist(aw, lpw)   // b=receiver, a=presser
            let stickyAIsReceiver = cost1 <= cost2

            // ROLE LOCK while engaged on the point (on-target / holding / pause-grace): mid-press the
            // two hands overlap so much that the nearest-target preference oscillates — on the forearm
            // points (PC6/SJ5, target extrapolated past the wrist) it repeatedly flipped the ring onto
            // the MASSAGING hand. Nobody swaps hands mid-press: while engaged, keep the sticky roles
            // and don't accumulate swap votes. Swaps confirm only while genuinely searching.
            let engaged = phase == .holding || phase == .onTargetUnstable || phase == .paused
            if engaged { swapVotes = 0; return commitRoles(aIsReceiver: stickyAIsReceiver, a: a, b: b) }

            // While searching, a disagreement only counts toward a swap when the swapped assignment
            // is CLEARLY better — near-tie geometry (overlapping hands) must not oscillate the ring.
            let stickyScore = stickyAIsReceiver ? sA : sB
            let prefScore   = stickyAIsReceiver ? sB : sA
            let clearlyBetter = prefScore < stickyScore * 0.65 && stickyScore - prefScore > 0.03
            if prefAIsReceiver == stickyAIsReceiver || !clearlyBetter { swapVotes = 0 } else { swapVotes += 1 }

            var aIsReceiver = stickyAIsReceiver
            if swapVotes >= CoachConst.swapConfirmFrames {
                aIsReceiver = prefAIsReceiver
                swapVotes = 0
                // Both roles flip to physically different hands — reset BOTH filters so neither the
                // ring nor the press tip lerps across the discontinuity, and drop the tip grace
                // (a stale tip must not bridge two different hands).
                smoother.reset(); pressSmoother.reset(); lastTipT = -.infinity
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
