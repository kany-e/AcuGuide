import SwiftUI
import Vision      // VNChirality — the locate window tracks the receiver's handedness per sample
import QuartzCore  // CACurrentMediaTime — confirmLocate's default latch clock (same clock as the camera frames)

enum CoachPhase: CaseIterable { case noHand, wrongFace, searching, onTargetUnstable, holding, resting, paused, complete }

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
    // nil-ing the tip / resetting its smoother / disengaging on a single missed frame. Held a bit
    // longer (0.3 → 0.5) so the intermittent top-down hand's dot stops FLICKERING on/off between reads —
    // still short enough that a finger that really lifts clears within half a second (user-reported).
    static let tipGraceS             = 0.5
    // How long a lone surviving hand may be treated as "the presser occluding the receiver" before
    // the assumption decays and roles reset (the hand becomes the receiver by the single-hand rule).
    // Unbounded, this state froze the ring forever and could self-latch a receiving hand as presser.
    static let lonePresserGraceS     = 1.5
    // A "confident" fingertip measurement — shared by the palm-glaze engagement gate and the
    // locate step's capture gate (was two independent 0.4 literals; review-caught).
    static let minTipConfidence: Float = 0.4
    // ── Presser-tip acquisition (user-directed) ─────────────────────────────────────────────────
    // The pressing fingertip is chosen as the nearest fingertip of a hand OTHER than the one the
    // acupoint sits on (the massaging hand can never be the receiving hand), within this radius of
    // the ring — so the receiver's OWN fingers and anything hovering far from the point are voided
    // ("only detect the finger tip that comes in the proximity of the acupoint, the rest voided").
    // Sized in hand-size units, generous enough that the dot appears as the finger approaches (and
    // an off-guide-but-near press still tracks so the cue can say "a little far" rather than losing
    // it); the acquire radius is floored at the exit band so a tip inside the exit band is always a
    // candidate. Only genuinely-far hovering (beyond ~2/3 of a hand) is voided.
    static let presserAcquireXHandSize: CGFloat = 0.65
    // Identity hold so the chosen tip doesn't flicker between two near-equidistant fingertips: the
    // held finger keeps the slot while it stays a candidate and isn't more than this isotropic margin
    // farther from the ring than the new nearest fingertip. Beyond that margin the press really moved
    // to another finger and we switch (and reset the tip smoother so it doesn't lerp across the gap).
    // Widened 0.04 → 0.08 so a noisy on-device fingertip stops hopping between fingers (user-reported
    // shaky tip) — still switches on a clear, sustained move to a different finger, so not rigid.
    static let presserHoldMargin: CGFloat = 0.08
    // ── Guided locate (find-it-by-feel ON CAMERA, before coaching starts) ──────────────────────
    // The user follows the plain-language guide, presses around the dashed "about here" ring, and
    // confirms the spot that feels right; the confirmed press becomes their personal correction.
    // The capture radius is measured from the PURE affine target (the same datum and iso units as
    // the storage clamp), so a gate-accepted press is never silently clamped away on save.
    static let locateCaptureRadiusXHandSize = 0.30   // a press this near the standard spot confirms normally
    // Your point may simply NOT be where the standard estimate puts it — anatomy varies, and the
    // affine estimate itself carries error. Blocking confirm outside the inner radius meant the one
    // feature whose entire purpose is "record where YOUR point is" refused to record it: the user
    // got "a little far, come back to the ring" and a dead button (device-reported).
    //
    // So presses out to this OUTER radius still settle and confirm — the UI just says plainly that
    // the spot is further from the standard location than usual, rather than silently refusing. The
    // inner radius keeps its meaning as "normal", and the guard against a stray press becoming a
    // permanent calibration becomes an informed choice instead of a locked door. Beyond THIS, the
    // press is treated as genuinely off-guide (a hand resting elsewhere, a mis-tap).
    // 0.45, deliberately NOT wider: selectPresserTip only acquires a fingertip within
    // presserAcquireXHandSize (0.65), so pushing this to ~0.55+ would squeeze the genuine
    // "off-guide" band (tracked, but too far) down to almost nothing and a mis-tap would read as a
    // confirmable spot. 0.45 gives ~50% more reach than the old 0.30 while leaving 0.45–0.65 as a
    // real off-guide range.
    static let locateFarCaptureRadiusXHandSize = 0.45
    static let locateWindowS   = 0.8    // trailing window of measured presses
    static let locateSteadyS   = 0.6    // the window must span this long before confirm unlocks
    // MEAN absolute deviation from the window centroid below this = a settled press. (Named
    // "MeanDev", not "Std": the sibling stabilityStdThreshold IS a true std in the round machine —
    // the two gates use different statistics and must not be tuned as a pair.)
    static let locateMeanDevXHandSize = 0.05
    // How long a tight-but-chirality-blocked press may sit in .settling before the cue turns
    // honest ("couldn't read the hand") instead of promising a settle that can never come.
    static let locateChirBlockedHintS = 2.5
    // ── Two-pass Vision dedup / backoff (CameraCoach) ───────────────────────────────────────────
    static let invertedBackoffStreak = 12    // no-yield passes before the inverted pass throttles
    static let invertedBackoffStride = 3     // …to every Nth frame (until a pass yields again)
    static let dupWristRadius: CGFloat = 0.15      // same-chirality reads this close = same hand
    static let dupConflictRadius: CGFloat = 0.05   // conflicting-label reads must be near-coincident
    static let dupConfidenceBias: Float = 0.1      // primary wins unless inverted beats it by this
    static let weakHandConfidence: Float = 0.3     // whole-hand floor for the weak (presser-only) tier
    // ── Handedness hold + face-gate escape (CoachEngine) ────────────────────────────────────────
    // Consecutive frames that must agree before the receiver's held handedness changes. Nobody
    // swaps pressing hands mid-session, so this can be generous; at 30 Hz it is a third of a second,
    // long enough to absorb Vision's misreads and short enough that a real hand change keeps up.
    static let chiralityFlipFrames = 10
    // How long the palm/back gate may refuse before the UI offers the user an override. Long enough
    // that someone genuinely holding the wrong side turns it over first (the cue is spoken within a
    // second), short enough not to strand someone the gate has simply misread.
    static let wrongFaceStuckS = 6.0
    // Once a press has settled (.ready), the offer stays open this long after the pressing
    // finger lifts — the user needs that hand to TAP the confirm button, and without a latch the
    // state decayed within tipGraceS and the button disabled before any physical tap could land
    // (review-caught: confirm was unreachable single-handed). The latch breaks early only if the
    // receiving hand leaves the frame or flips face — the captured geometry is void then.
    static let locateConfirmLatchS = 4.0
}

// Whether the engine is in the guided-locate step (find the spot by feel, camera labels the
// press) or normal press coaching (the round machine).
enum CoachMode { case locate, coach }

// What the locate step sees this frame — drives the locate card's cue + confirm button.
enum LocateState: CaseIterable { case noHand, wrongFace, noPress, offGuide, settling, ready }

// The HIGH-RATE overlay stream (ring, press dot, labeled press, saved-spot dot, hold progress),
// separated from CoachEngine so its per-frame writes invalidate ONLY the compact overlay/progress
// subviews. On the engine these writes fired objectWillChange 30×/s and re-evaluated the ENTIRE
// full-screen coach body every camera frame — defeating the engine's own carefully guarded
// transition writes (review-caught). Values are engine-written on the main thread.
final class CoachOverlay: ObservableObject {
    @Published var ringCenter: CGPoint? = nil      // normalized, top-left origin (smoothed)
    @Published var ringRadius: CGFloat = 0          // fraction of the frame WIDTH (isotropic units)
    @Published var pressTip: CGPoint? = nil
    @Published var locateCandidate: CGPoint? = nil  // the labeled press ("your press")
    @Published var savedSpot: CGPoint? = nil        // re-locate: where the stored correction sits
    @Published var progress: Double = 0             // 0...1 hold completion of the CURRENT round
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
    // Vision confidence of the tip MEASUREMENT behind offsetXHandSize (0 = the DIP/PIP
    // reconstruction — an unmeasured guess). Rides the input struct so locate behavior stays
    // reproducible from CoachFrameInput alone (fixtures default to fully reliable).
    var tipConfidence: Float = 1
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

    // Engagement as of the LAST step — the single source for "was the press engaged a frame ago"
    // (the engine used to reconstruct this from its own published phase with two different member
    // sets; review-caught drift risk).
    var isEngaged: Bool { engaged }

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
    @Published var cue: String = "Bring your hand into the frame."

    // The 30 Hz stream lives on its own object (see CoachOverlay); the engine keeps read-only
    // forwarders so tests and non-view callers keep one API.
    let overlay = CoachOverlay()
    var ringCenter: CGPoint? { overlay.ringCenter }
    var ringRadius: CGFloat { overlay.ringRadius }
    var pressTip: CGPoint? { overlay.pressTip }
    var locateCandidate: CGPoint? { overlay.locateCandidate }
    var progress: Double { overlay.progress }

    // Guided-locate layer (see CoachMode/LocateState). While locating, the round machine is never
    // stepped — no hold time, no rounds — the engine just tracks whether a confident press has
    // settled near the guide ring so the user can confirm "this is the spot".
    @Published private(set) var mode: CoachMode
    @Published private(set) var locateState: LocateState = .noPress
    private let initialMode: CoachMode
    // Recent measured (smoothed) tips + the receiver's chirality that frame — a settled press
    // must also have STABLE, KNOWN handedness (a chirality misread mirrors the stored fold).
    private var locateWindow: [(t: Double, p: CGPoint, chir: VNChirality)] = []
    // The receiver + PURE affine target + hand scale that travel together through the locate
    // step: one struct so a partial snapshot is unrepresentable (was six parallel optionals).
    private struct LocateAnchors { var hand: Hand; var affine: CGPoint; var handScale: CGFloat }
    private var frameAnchors: LocateAnchors? = nil      // this frame's (every resolvable frame)
    // The CAPTURE-TIME snapshot confirmLocate actually uses — committed only on frames that
    // append a press sample, so a confirm never pairs an old press with a hand that moved during
    // the tip-grace/latch window (review-caught skew). capturedPress is the frozen press for the
    // CONFIRM MATH; its canonical twin re-projects the on-screen "your press" marker through the
    // LIVE hand pose while the offer is latched (the frozen screen point visibly detached from a
    // relaxing hand — review-caught).
    private var capturedAnchors: LocateAnchors? = nil
    private var capturedPress: CGPoint? = nil
    private var capturedCanonical: (x: Double, y: Double)? = nil
    // When .ready was last backed by LIVE measurements — the confirm latch anchor.
    private var lastLiveReadyT = -Double.infinity
    // The offer just lapsed (latch expiry, not confirm/hand-loss) — keys an honest "timed out,
    // press again" cue instead of reverting to the beginner instruction.
    private var latchLapsed = false
    // Since when a tight, in-radius press has been blocked ONLY by unreadable handedness — after
    // locateChirBlockedHintS the cue says so instead of promising "hold still" forever.
    private var chirBlockedSince: Double? = nil
    // Front camera = coaching your own hand; back camera = coaching SOMEONE ELSE'S (two-person
    // mode) — the few cues that address "your hand" switch person on this flag.
    var selfCoaching = true
    let calibration: PointCalibration              // injectable so tests run on a clean store;
                                                   // exposed so LocateCard reads the SAME store

    // Portrait display aspect (W/H, <1) of the live frame — set by CameraCoach before each update.
    // Landmarks arrive normalized PER AXIS (x/W, y/H), which is anisotropic: 1.0 of y spans ~1.78×
    // the pixels of 1.0 of x on a 9:16 frame. All hit-test geometry below therefore measures in
    // ISOTROPIC width units via isoDist — otherwise the accept region is a tall ellipse ~1.78× the
    // drawn ring vertically, and handSize swings ~1.78× with hand rotation (review-caught).
    var frameAspect: CGFloat = 9.0 / 16.0

    // Isotropic distance in width units: y-offsets are scaled by H/W (= 1/frameAspect).
    private func isoDist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = (a.y - b.y) / max(frameAspect, 0.1)
        return (dx * dx + dy * dy).squareRoot()
    }
    // Hand scale (wrist → middle MCP) in the same isotropic width units, so tolerance fractions
    // don't inflate/shrink with hand orientation.
    private func isoHandSize(_ h: Hand) -> CGFloat? {
        guard let w = h.p(.wrist), let m = h.p(.middleMCP) else { return nil }
        return isoDist(w, m)
    }

    // Session layer: repeated press/release rounds on top of the validated per-round state machine
    // (the machine itself stays a pure single-hold automaton — fixtures still validate it).
    @Published private(set) var roundsDone = 0
    @Published private(set) var sessionComplete = false
    let roundsTarget: Int
    private let restS: Double
    // Release gap between rounds, counted down by FRAME time (dt-clamped) rather than a wall-clock
    // deadline: frames stop while the user pauses or app-switches, so the guided rest freezes with
    // them instead of silently expiring behind a pause overlay that promised "progress is kept".
    private var restLeft: Double? = nil             // non-nil while in the release gap
    private var restLastT: Double = 0               // last frame timestamp seen during the gap
    private var restRemaining = 0                   // whole seconds, for the rest cue
    private var heldAccum = 0.0                     // banked hold seconds from finished rounds
    var totalHeldS: Double { heldAccum + machine.holdTime }   // for the recap (quit-anytime honest)
    private(set) var roundTimes: [Double] = []      // hold seconds per COMPLETED round (recap breakdown)

    // Secondary "why is nothing happening" line under the main cue — set only when the receiving
    // hand's geometry has been unresolvable for a while (occlusion), so it never flashes on the
    // routine one-frame dropouts the grace timers already absorb.
    @Published private(set) var hintText: String? = nil
    // The settled press is confirmable but sits further from the standard estimate than a typical
    // anatomical fine-tune. Drives an honest note on the confirm card — never a block.
    @Published private(set) var locateFarFromStandard = false
    private var anchorLostSince: Double? = nil

    private let machine: CoachStateMachine

    init(roundsTarget: Int = CoachConst.sessionRounds,
         roundHoldS: Double = CoachConst.holdTargetS,
         restS: Double = CoachConst.restS,
         startLocating: Bool = false,
         calibration: PointCalibration = .shared) {
        self.roundsTarget = roundsTarget
        self.restS = restS
        self.machine = CoachStateMachine(holdTargetS: roundHoldS)
        self.initialMode = startLocating ? .locate : .coach
        self.mode = initialMode
        self.calibration = calibration
    }
    // Target ring. Was the light web default (minCutoff 1.0, beta 1.5) which left the acupoint ring
    // jittering with the receiving hand's noisy landmarks (user-reported "too shaky"). Heavier now
    // (minCutoff 0.5 — more smoothing at rest, beta 1.0) so the ring sits steady on a held hand while
    // still following a deliberate move; the hand is mostly still during coaching so the small extra
    // lag is worth it. (Fixtures press a STATIONARY hand → constant input → One-Euro is exact, unaffected.)
    private let smoother = OneEuroPoint(OneEuroOptions(minCutoff: 0.5, beta: 1.0, dCutoff: 1.0))
    // Second-hand press tip. One-Euro has two ORTHOGONAL dials: minCutoff = jitter at REST, beta = lag
    // during MOTION. minCutoff 0.30 keeps the tip rock-steady while pressing (the user's "shaky" report).
    // But beta had been dropped to 0.4, which over-smoothed MOTION so the dot LAGGED behind the moving
    // fingertip (user: "not accurately at the finger tip"). Restored beta to 1.2 so it tracks the finger
    // as it moves onto the point, while staying smooth at rest (the velocity estimate is dCutoff-filtered,
    // so resting noise doesn't spike the cutoff). The hand-jump shake is handled upstream by the face gate.
    private let pressSmoother = OneEuroPoint(OneEuroOptions(minCutoff: 0.30, beta: 1.2, dCutoff: 1.0))

    // Sticky two-hand role tracking (stops the ring jumping between hands).
    private var lastReceiverWrist: CGPoint? = nil
    private var lastPresserWrist: CGPoint? = nil
    private var swapVotes = 0

    // Held pressing-finger identity (which fingertip is currently the presser) so the press dot doesn't
    // flicker between near-equidistant fingertips, and so the caller can tell a genuine finger SWITCH
    // (reset the tip smoother) from a continuous same-finger track (keep smoothing). There is only ever
    // one non-receiver hand (maximumHandCount 2, receiver excluded), so the finger enum alone identifies
    // it — no wrist tracking needed. Kept across a brief no-candidate dropout so a re-acquire of the SAME
    // finger doesn't read as a switch.
    private var heldPresserFinger: HandJoint? = nil

    // Last face verdict that we could actually compute — reused when a frame can't verify the
    // face (a required MCP landmark dropped) so a brief occlusion doesn't flip to WRONG_FACE
    // and reset the steadiness run.
    private var lastFaceCorrect = false

    // HELD HANDEDNESS for the receiving hand, and the votes for changing it.
    //
    // Vision re-decides chirality independently on every frame, from image content alone, and the
    // coach's framing — two overlapping hands filling the frame, no forearm, no body — is its worst
    // case. Handedness is the sign multiplier inside isDorsal, so one misread frame inverts the
    // palm/back verdict and the coach tells the user to turn over a hand that is already correct
    // (device report: "I tried my left hand and it tells me to flip even though it's the correct
    // side"). Nobody swaps which hand they are pressing mid-session, so the label is held and only
    // changes after several consecutive frames agree — the same shape as the sticky role swap
    // above, applied to the one other per-frame identity the coach depends on.
    private var heldChirality: VNChirality = .unknown
    private var chiralityVotes = 0

    // WHEN THE GATE IS WRONG ANYWAY. Holding the label makes a misread rare, not impossible, and
    // palm-vs-back from a 2D image is a heuristic even with a perfect label — the web original that
    // this test was ported from called it "only moderately reliable" and scored 7/8. Its cost when
    // wrong is a HARD BLOCK: the confirm button is disabled and the coach repeats "turn your hand
    // over" at someone whose hand is already the right way up, with no way out (the only override
    // shipped was #if DEBUG). So: after a stuck stretch, say so and let the user overrule it.
    private var wrongFaceSince: Double? = nil
    /// The face gate has been refusing for long enough to offer the user an override.
    @Published private(set) var faceGateStuck = false
    /// Set by the user overruling the gate. Session-scoped, never persisted, and never inferred.
    private(set) var faceOverridden = false
    func overrideFaceGate() {
        faceOverridden = true
        faceGateStuck = false
        wrongFaceSince = nil
    }

    /// Drop the held label and the stuck-gate timer — for a new scene, a new session, or a frame
    /// with no usable hand. Deliberately does NOT clear `faceOverridden`: a user who has overruled
    /// the gate should not have to do it again every time their hand briefly leaves the frame.
    private func forgetHandedness() {
        heldChirality = .unknown; chiralityVotes = 0
        wrongFaceSince = nil
        if faceGateStuck { faceGateStuck = false }
    }

    /// The handedness to reason with this frame: the held label, updated only on a sustained change.
    private func holdChirality(_ observed: VNChirality) -> VNChirality {
        guard observed != .unknown else { return heldChirality }   // a blank read is not a vote
        if observed == heldChirality { chiralityVotes = 0; return heldChirality }
        if heldChirality == .unknown { heldChirality = observed; chiralityVotes = 0; return heldChirality }
        chiralityVotes += 1
        if chiralityVotes >= CoachConst.chiralityFlipFrames {
            heldChirality = observed
            chiralityVotes = 0
        }
        return heldChirality
    }

    // When the press tip was last actually measured — drives the tipGraceS dropout grace.
    private var lastTipT = -Double.infinity

    // When the lone-presser (receiver occluded) state began — bounds it to lonePresserGraceS.
    private var lonePresserSince: Double? = nil

    // Last MEASURED target, in the canonical (hand-relative) frame, plus its hand scale. When the
    // pressing finger covers an anchor — the normal state of a correct press — the ring reprojects
    // from this instead of vanishing, so it keeps tracking the hand rather than freezing at stale
    // screen coordinates. Written only from a real weightedTarget measurement, never from a
    // reprojection, so it cannot drift by compounding on itself. Cleared with the rest of the
    // scene-keyed state on a camera flip / reset (both spaces change).
    private var lastCanonicalTarget: (x: Double, y: Double)? = nil
    private var lastHandScale: CGFloat? = nil

    // A camera flip is a NEW SCENE in a different coordinate parity: drop everything keyed to the
    // old one — smoothers, sticky role anchors, the face verdict, the lone-presser assumption, and
    // the on-screen ring/tip (their positions are meaningless in the new frame).
    func cameraFlipped() {
        smootherReset(); roleReset()
        lastFaceCorrect = false; lonePresserSince = nil
        forgetHandedness()   // a new scene may well be a different physical hand
        lastCanonicalTarget = nil; lastHandScale = nil   // canonical frame is parity-dependent
        overlay.ringCenter = nil; overlay.pressTip = nil
        resetLocateTracking()   // window/candidate/anchors are all in the old coordinate parity
        // Frames are scene-generation-dropped until the flip's reconfigure commits, so nothing
        // recomputes the cue for ~0.5s — refresh it NOW to match the state just published, or the
        // card shows "tap this is my spot" beside a disabled button (review-caught).
        if mode == .locate {
            let line = locateCue(.noPress, point: nil, now: 0)
            if cue != line { cue = line }
        }
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
        machine.reset(); smootherReset(); roleReset()
        lastFaceCorrect = false; lonePresserSince = nil
        forgetHandedness()
        faceOverridden = false   // an override is the user's call for THIS session, never inherited
        lastCanonicalTarget = nil; lastHandScale = nil
        roundsDone = 0; sessionComplete = false; restLeft = nil; heldAccum = 0
        roundTimes = []; clearHint()
        phase = .noHand; overlay.ringCenter = nil; overlay.pressTip = nil; overlay.progress = 0
        mode = initialMode
        resetLocateTracking()
        cue = AppLocale.pick("把手放到镜头前就好。", "Bring your hand into view whenever you're ready.")
    }

    private func resetLocateTracking() {
        locateWindow.removeAll()
        if locateCandidate != nil { overlay.locateCandidate = nil }
        if overlay.savedSpot != nil { overlay.savedSpot = nil }
        if locateState != .noPress { locateState = .noPress }
        frameAnchors = nil
        capturedAnchors = nil; capturedPress = nil; capturedCanonical = nil
        lastLiveReadyT = -.infinity
        latchLapsed = false
        chirBlockedSince = nil
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
            phase = .searching; overlay.ringCenter = nil; overlay.pressTip = nil; return
        }

        // Release gap between rounds — timer-driven, NOT machine-driven: the user is told to let go,
        // so hands leaving the frame is expected and must not flash NO_HAND. The last ring stays on
        // screen (dim) as the guide back; the round machine restarts clean when the gap ends.
        if let left = restLeft {
            let d = min(max(0, now - restLastT), CoachConst.maxFrameDtS)   // clamp: a pause/app-switch gap counts as one frame
            restLastT = now
            let remaining = left - d
            if remaining > 0 {
                restLeft = remaining
                restRemaining = Int(remaining.rounded(.up))
                overlay.pressTip = nil
                clearHint()
                apply(.resting, point: point, hasPresser: false)
                return
            }
            restLeft = nil                                             // machine was reset when the gap began
            smootherReset()
        }

        // 1) No usable hand.
        guard !hands.isEmpty else {
            lonePresserSince = nil
            stepNoUsableHand(now, point: point)
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
        let weakHands = hands.filter { $0.weak }
        var receiverOpt: Hand?
        var presser: Hand?
        if strongHands.isEmpty {
            (receiverOpt, presser) = (nil, hands.first)
        } else {
            (receiverOpt, presser) = assignRoles(strongHands, target: target, requiresDorsal: point.requiresDorsal)
            if presser == nil, receiverOpt != nil { presser = weakHands.first }
        }
        if receiverOpt == nil {
            let since = lonePresserSince ?? now
            lonePresserSince = since
            if now - since > CoachConst.lonePresserGraceS {
                if strongHands.isEmpty {
                    // Only weak hands remain past the grace: nothing here can hold the ring.
                    // Read as "no usable receiving hand" (keep `lonePresserSince` stale so this
                    // doesn't re-arm a fresh grace every frame while weak-only persists).
                    stepNoUsableHand(now, point: point)
                    return
                }
                roleReset(); lonePresserSince = nil
                (receiverOpt, presser) = assignRoles(strongHands, target: target, requiresDorsal: point.requiresDorsal)   // lone strong hand = receiver
            }
        } else {
            lonePresserSince = nil
        }
        guard let receiver = receiverOpt else {
            // Receiver occluded: resolve the press dot through the SAME selectPresserTip path as the
            // main press (any finger, identity-hold, changed→smoother-reset), gated to the LAST known
            // ring (there's no fresh one) — so a non-index press and the tip smoother stay consistent
            // across the occlusion boundary, and only a fingertip near the last point is painted (not a
            // stray/weakly-seen hand far away, the wrong-hand jump). No ring ever established → no
            // reference → no dot. Brief dropout keeps the last dot within tipGraceS; expired clears.
            if let ring = overlay.ringCenter,
               let measured = selectPresserTip(hands: hands, receiverWrist: nil, ringCenter: ring,
                                               acquireRadius: max(overlay.ringRadius * 3, 0.12)) {
                if measured.changed { pressSmoother.reset() }
                overlay.pressTip = pressSmoother.filter(measured.point, now); lastTipT = now
            } else if pressTip != nil, now - lastTipT <= CoachConst.tipGraceS {
                // keep the last dot
            } else {
                overlay.pressTip = nil; pressSmoother.reset()
            }
            // The receiving hand has been occluded past the transient window — say so, plainly.
            occlusionHint(now, AppLocale.pick("让被按的那只手多露出来一些。",
                                              "Let the hand being pressed peek back into view."))
            step(occludedInput(now), point: point, hasPresser: presser != nil)
            return
        }

        // 3) Geometry. The receiving hand IS present but a target anchor may be momentarily
        // unresolvable (e.g. the pressing finger occludes the ring/pinky knuckles — the exact
        // case smoothing exists for). Treat that as present-but-no-contact so a brief occlusion
        // PAUSES within grace (via the dropout debounce) instead of flashing NO_HAND and wiping
        // the steadiness run. Keep the last ring; drop the now-stale press tip. Do NOT reset the
        // smoother — geometry resumes continuously.
        // PRESSING THE POINT OCCLUDES THE POINT. weightedTarget is all-or-nothing — one missing
        // anchor returns nil — and Vision discards any landmark under 0.3 confidence. TE3's anchors
        // are ringMCP (0.11), pinkyMCP (0.47) and wrist (0.42), while the point itself is the groove
        // BEHIND the ring/little knuckles, so the pressing finger lands squarely on two of its three
        // anchors. Losing the 11%-weight one was enough to null the target.
        //
        // This branch used to answer that by clearing the press dot outright and reporting
        // hasPresser: false — bypassing the tipGraceS grace the sibling receiver-occluded path uses.
        // Device-reported result: the dot flickered on and off as anchors crossed the confidence
        // line, and the ring froze and jumped, "when the pressing finger comes into the circle".
        // Pinned by testAnchorOccludedByThePressingFingerDoesNotKillTheDot (6/6 frames lost before).
        //
        // Occlusion here is the NORMAL state of a correct press, not a failure, so it is ridden out
        // rather than reported: the ring reprojects from the canonical hand frame (which needs only
        // wrist + middleMCP, still visible when a knuckle is covered) so it keeps TRACKING the hand
        // instead of freezing, and the press dot resolves through the same selectPresserTip + grace
        // path as everywhere else.
        var resolvedCenter = receiver.weightedTarget(target.anchors)
        var resolvedScale = isoHandSize(receiver)
        if resolvedCenter == nil || (resolvedScale ?? 0) <= 0,
           let q = lastCanonicalTarget,
           let ridden = PointCalibration.reproject(q, hand: receiver, aspect: frameAspect) {
            resolvedCenter = ridden
            if (resolvedScale ?? 0) <= 0 { resolvedScale = lastHandScale }   // scale is slower-moving
        }
        guard let rawCenter = resolvedCenter, let handScale = resolvedScale, handScale > 0 else {
            // Nothing left to ride: even the canonical frame is gone (no wrist/middleMCP, or the
            // hand has never resolved once). Keep the dot within its grace rather than hard-clearing.
            if pressTip != nil, now - lastTipT <= CoachConst.tipGraceS {
                step(occludedInput(now), point: point, hasPresser: true)
            } else {
                overlay.pressTip = nil; pressSmoother.reset()
                occlusionHint(now, AppLocale.pick("让手腕和指节露出来一点。",
                                                  "Let the wrist and knuckles peek into view."))
                step(occludedInput(now), point: point, hasPresser: false)
            }
            return
        }
        clearHint()   // geometry is resolving again
        let hs = handScale
        // Cache the resolved geometry in the CANONICAL (hand-relative) frame so the next occluded
        // frame can ride it. Only cached from a genuine measurement, never from a reprojection, so
        // the estimate can't drift by compounding on itself.
        if receiver.weightedTarget(target.anchors) != nil {
            lastCanonicalTarget = PointCalibration.canonical(rawCenter, hand: receiver, aspect: frameAspect)
            lastHandScale = hs
        }
        // M1 shadow mode: run the learned CoreML head next to the affine target + log the delta. Never
        // alters the ring/state machine — reads the hand only. See LearnedLocalizer / M1 experiment.
        ShadowLocalizer.shared.record(hand: receiver, point: point, affine: rawCenter, handSize: hs, pressing: presser != nil)
        // Per-user spot correction (guided locate): the stored canonical-frame offset rides this
        // frame's hand pose. Shadow above stays on the PURE affine — it measures learned−affine.
        let corrected = calibration.apply(rawCenter, hand: receiver, pointId: point.id, aspect: frameAspect)
        // ONE datum per mode. LOCATE guides from the STANDARD spot: the dashed ring, the capture
        // gate, and the storage clamp all share the pure affine target (drawing the corrected spot
        // while gating on affine made the cue point somewhere the gate wasn't — review-caught);
        // any existing correction shows as a small separate "saved spot" dot instead, so a
        // re-locate is unbiased but the old answer stays visible. COACH coaches the corrected spot.
        let guideTarget: CGPoint
        if mode == .locate {
            guideTarget = rawCenter
            frameAnchors = LocateAnchors(hand: receiver, affine: rawCenter, handScale: hs)
            overlay.savedSpot = calibration.hasCalibration(point.id) ? corrected : nil
        } else {
            guideTarget = corrected
            if overlay.savedSpot != nil { overlay.savedSpot = nil }
        }
        let center = smoother.filter(guideTarget, now)   // One-Euro BEFORE hit-test + draw
        let tol = target.toleranceXHandSize * hs
        overlay.ringCenter = center
        overlay.ringRadius = tol

        // 4) Face gate, against the HELD handedness rather than this frame's raw read (see
        // holdChirality). isDorsal is nil when a required MCP landmark is missing OR when no
        // handedness is known yet; in either case reuse the last verdict we could compute, so
        // neither a transient occlusion nor an unreadable label flips to WRONG_FACE.
        var faceCorrect: Bool
        if let dorsal = receiver.isDorsal(assuming: holdChirality(receiver.chirality)) {
            faceCorrect = point.requiresDorsal ? dorsal : !dorsal
            lastFaceCorrect = faceCorrect
        } else {
            faceCorrect = lastFaceCorrect
        }
        // Track how long the gate has been refusing, then offer the escape (see faceGateStuck).
        if faceCorrect {
            wrongFaceSince = nil
            if faceGateStuck { faceGateStuck = false }
        } else if let since = wrongFaceSince {
            let stuck = now - since >= CoachConst.wrongFaceStuckS
            if stuck != faceGateStuck { faceGateStuck = stuck }
        } else {
            wrongFaceSince = now
        }
        if faceOverridden { faceCorrect = true }

        // 5) Press tip + contact. The pressing fingertip is now the nearest fingertip of a hand OTHER
        // than the receiver, within an acquire radius of the ring (selectPresserTip) — so the receiver's
        // own fingers and anything hovering far away can never be tracked as the press (user-directed).
        // The second (massaging) hand's fingertip is noisy in Vision, so One-Euro-smooth it BEFORE the
        // contact test and before drawing (mirrors the target ring). The tip is also the joint Vision
        // DROPS most (it's doing the occluding), so a transient loss gets a short grace (tipGraceS):
        // keep the last dot on screen and step the machine as inside-the-exit-band with NO offset —
        // engagement survives via the dropout debounce, but hold time never advances on unverifiable
        // geometry (same rule as receiver occlusion). Only after the grace expires does the tip clear +
        // the filter reset (a longer gap means the finger really left; restarting the filter clean
        // avoids a stale-velocity lerp back).
        var inEnter = false, inExit = false, hasPresser = false
        var offN: Double? = nil
        var tipConf: Float = 1
        // Generous enough that the dot appears as the finger approaches, but never below the exit band
        // so a tip inside the exit band is always a candidate.
        let acquireRadius = max(hs * CoachConst.presserAcquireXHandSize, tol * CoachConst.exitRadiusMult)
        if let measured = selectPresserTip(hands: hands, receiverWrist: receiver.p(.wrist),
                                           ringCenter: center, acquireRadius: acquireRadius) {
            if measured.changed { pressSmoother.reset() }   // new physical fingertip — don't lerp from the old one
            let tip = pressSmoother.filter(measured.point, now)
            overlay.pressTip = tip; hasPresser = true
            lastTipT = now
            tipConf = measured.confidence
            // Contact distance vs the displayed guide — which is now the SAME datum the storage
            // clamp uses in locate mode (guideTarget above), so an accepted press always stores
            // without silent truncation (review-caught re-calibration mismatch).
            let dd = isoDist(tip, center)
            // Palm-glaze gate (user-reported: "whatever hand part glazes over the area, it tracks"):
            // when a palm covers the target, Vision still hallucinates a LOW-confidence tip under it,
            // which used to start engagement. A NEW engagement now needs a confident tip; an ongoing
            // hold doesn't (mid-press confidence dips must not break HOLDING — hysteresis as usual).
            // The confidence comes from the pressTip MEASUREMENT itself, so the DIP/PIP-reconstructed
            // tip (confidence 0 — an unmeasured guess) can sustain but never start an engagement.
            // Fixture/test hands carry no confidences → default reliable, so the validated paths hold.
            let wasEngaged = machine.isEngaged
            inEnter = dd < tol && (measured.confidence >= CoachConst.minTipConfidence || wasEngaged)
            inExit = dd < tol * CoachConst.exitRadiusMult
            offN = Double(dd / hs)
        } else if pressTip != nil, now - lastTipT <= CoachConst.tipGraceS {
            hasPresser = true                       // brief dropout: keep the dot + cue steady
            inExit = true                           // stay in the exit band → debounce governs
        } else {
            overlay.pressTip = nil; pressSmoother.reset()   // presser really gone — restart the filter clean
        }

        step(CoachFrameInput(
            t: now, present: true, faceCorrect: faceCorrect,
            insideEnterRadius: inEnter, insideExitRadius: inExit, offsetXHandSize: offN,
            tipConfidence: tipConf),
            point: point, hasPresser: hasPresser)
    }

    private func noHandInput(_ now: TimeInterval) -> CoachFrameInput {
        CoachFrameInput(t: now, present: false, faceCorrect: false,
                        insideEnterRadius: false, insideExitRadius: false, offsetXHandSize: nil)
    }

    // Present-but-unverifiable frame (occluded receiver / unresolvable anchors): inside the exit
    // band so the dropout debounce governs, with no measurable offset.
    private func occludedInput(_ now: TimeInterval) -> CoachFrameInput {
        CoachFrameInput(t: now, present: true, faceCorrect: true,
                        insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: nil)
    }

    // The full no-usable-hand teardown + step, shared by the empty-frame and weak-only exits
    // (was two near-verbatim inline blocks).
    private func stepNoUsableHand(_ now: TimeInterval, point: Acupoint) {
        smootherReset(); roleReset(); lastFaceCorrect = false
        forgetHandedness()   // the held label described a hand that has left the frame
        lastCanonicalTarget = nil; lastHandScale = nil   // no hand → nothing to ride
        overlay.ringCenter = nil; overlay.pressTip = nil
        clearHint()   // the NO_HAND cue already says what to do
        step(noHandInput(now), point: point, hasPresser: false)
    }

    // THE mode dispatch seam — every update() exit routes through here: coach mode drives the
    // round machine (+ its round/rest bookkeeping), locate mode drives the locate tracker.
    private func step(_ f: CoachFrameInput, point: Acupoint, hasPresser: Bool) {
        if mode == .locate { stepLocate(f, point: point, hasPresser: hasPresser) }
        else { stepCoach(f, point: point, hasPresser: hasPresser) }
    }

    // Coach mode: the validated round machine + session-round bookkeeping.
    private func stepCoach(_ f: CoachFrameInput, point: Acupoint, hasPresser: Bool) {
        let result = machine.step(f)

        // Round finished: bank its hold seconds, then either the whole SESSION is done or the
        // release-and-breathe gap starts. (Only a fully-measured frame can newly complete a
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
                restLeft = restS
                restLastT = f.t
                restRemaining = Int(restS.rounded(.up))
                overlay.pressTip = nil
                apply(.resting, point: point, hasPresser: false)
                return
            }
        }

        if result == .wrongFace { overlay.pressTip = nil }   // ring stays to guide the flip
        apply(result, point: point, hasPresser: hasPresser)
    }

    // MARK: - Guided locate (find the spot by feel; the camera labels the press)

    // Per-frame locate logic, run INSTEAD of the round machine while the user finds the spot.
    // A confident measured press (reconstructed tips carry confidence 0 and never count) inside
    // the capture radius accumulates in a trailing window; once the window is long, still, and
    // chirality-stable, the state goes .ready and the confirm button unlocks. From then on the
    // CONFIRM LATCH holds the offer open (locateConfirmLatchS) while the pressing finger lifts
    // and travels to the button — moving/vanishing tips must not revoke it, only the receiving
    // hand leaving the frame or flipping face does. Nothing is credited here.
    private func stepLocate(_ f: CoachFrameInput, point: Acupoint, hasPresser: Bool) {
        let now = f.t
        // ONE name for "the confirm offer is live and held open" (was the same negated predicate
        // re-derived in three branches; review-caught). `state` below starts as the entering
        // locateState, so this is valid across all arms.
        let offerLatched = locateState == .ready && now - lastLiveReadyT <= CoachConst.locateConfirmLatchS
        var state = locateState
        if !f.present {
            state = .noHand
            breakLocateSearch()
        } else if !f.faceCorrect {
            state = .wrongFace
            breakLocateSearch()
        } else if let off = f.offsetXHandSize, let tip = pressTip,
                  f.tipConfidence >= CoachConst.minTipConfidence {
            if off > CoachConst.locateFarCaptureRadiusXHandSize {
                // A tracked far press mid-latch is the pressing hand REACHING FOR THE BUTTON —
                // keep the offer. Otherwise it's a genuine off-guide search.
                if !offerLatched { state = .offGuide; locateWindow.removeAll() }
            } else {
                // Inside the outer band: confirmable, but say so honestly when it is further out
                // than a typical anatomical fine-tune.
                let far = off > CoachConst.locateCaptureRadiusXHandSize
                if locateFarFromStandard != far { locateFarFromStandard = far }
                latchLapsed = false
                locateWindow.append((now, tip, frameAnchors?.hand.chirality ?? .unknown))
                pruneLocateWindow(before: now - CoachConst.locateWindowS)
                switch settleVerdict(now) {
                case .settled:
                    state = .ready
                    chirBlockedSince = nil
                    // Candidate + anchors snapshot together, at MEASUREMENT time — a confirm
                    // always pairs the press with the hand pose that produced it. The canonical
                    // twin drives the display re-projection while the offer is latched.
                    let c = locateCentroid()
                    capturedPress = c
                    capturedAnchors = frameAnchors
                    capturedCanonical = frameAnchors.flatMap {
                        PointCalibration.canonical(c, hand: $0.hand, aspect: frameAspect)
                    }
                    if overlay.locateCandidate != c { overlay.locateCandidate = c }
                    lastLiveReadyT = now
                case .chiralityBlocked:
                    chirBlockedSince = chirBlockedSince ?? now
                    if !offerLatched { state = .settling }
                case .unsettled:
                    chirBlockedSince = nil
                    if !offerLatched { state = .settling }
                }
            }
        } else {
            // No confident measurement this frame. The latch holds a live .ready offer through
            // the lift-to-tap; the tip grace (hasPresser) holds other states through a one-frame
            // dropout; a real absence restarts the search.
            pruneLocateWindow(before: now - CoachConst.locateWindowS)
            if !offerLatched {
                let expiring = state == .ready   // an un-confirmed offer is lapsing right now
                if !hasPresser { state = .noPress; locateWindow.removeAll() }
                else if locateWindow.isEmpty, state == .ready || state == .settling { state = .noPress }
                if expiring, state != .ready { latchLapsed = true }
            }
        }

        // While the offer is latched with no fresh press, the "your press" marker rides the LIVE
        // hand pose (canonical re-projection) instead of freezing at stale screen coordinates —
        // the confirm math still uses the frozen capturedPress/capturedAnchors pair.
        if state == .ready, let q = capturedCanonical, let fa = frameAnchors,
           let ridden = PointCalibration.reproject(q, hand: fa.hand, aspect: frameAspect),
           overlay.locateCandidate != ridden {
            overlay.locateCandidate = ridden
        }

        if state != .ready, locateCandidate != nil { overlay.locateCandidate = nil }
        if locateState != state { locateState = state }
        let newCue = locateCue(state, point: point, now: now)
        if cue != newCue { cue = newCue }
    }

    // The receiving hand vanished or flipped: the captured geometry is void — break the offer,
    // the window, and the lapse flag together.
    private func breakLocateSearch() {
        if locateFarFromStandard { locateFarFromStandard = false }
        locateWindow.removeAll()
        lastLiveReadyT = -.infinity
        latchLapsed = false
        chirBlockedSince = nil
    }

    private func pruneLocateWindow(before cutoff: Double) {
        while let first = locateWindow.first, first.t < cutoff { locateWindow.removeFirst() }
    }

    private func locateCentroid() -> CGPoint {
        guard !locateWindow.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for e in locateWindow { x += e.p.x; y += e.p.y }
        let n = CGFloat(locateWindow.count)
        return CGPoint(x: x / n, y: y / n)
    }

    // Settled = the window spans locateSteadyS, the presses cluster tightly (MEAN isotropic
    // deviation from the centroid, in hand-size units, below the threshold), and the receiver's
    // handedness read KNOWN and CONSTANT across the window — a one-frame chirality misread at
    // capture would mirror the stored correction across the hand axis. The chirality failure is
    // reported apart from plain jitter so a persistent one gets an HONEST cue instead of an
    // endless "hold still" (review-caught soft-lock).
    private enum SettleVerdict { case settled, unsettled, chiralityBlocked }
    private func settleVerdict(_ now: Double) -> SettleVerdict {
        guard let first = locateWindow.first, now - first.t >= CoachConst.locateSteadyS,
              locateWindow.count >= 4, let hs = frameAnchors?.handScale, hs > 0 else { return .unsettled }
        let c = locateCentroid()
        let dev = locateWindow.reduce(0.0) { $0 + Double(isoDist($1.p, c)) } / Double(locateWindow.count)
        guard dev / Double(hs) < CoachConst.locateMeanDevXHandSize else { return .unsettled }
        guard first.chir != .unknown, locateWindow.allSatisfy({ $0.chir == first.chir }) else {
            return .chiralityBlocked
        }
        return .settled
    }

    // The user confirms "this is the spot": store press−target as their personal correction for
    // this point (canonical hand frame; clamped in PointCalibration so it stays a SLIGHT
    // correction), then hand over to the coach — the ring now sits where they pressed.
    // `now` guards the latch by the same frame clock the tracker uses (default = the live camera
    // clock): frames stop during a pause/background, so without this a frozen .ready stayed
    // confirmable for unbounded wall time (review-caught).
    @discardableResult
    func confirmLocate(point: Acupoint, now: Double = CACurrentMediaTime()) -> Bool {
        guard mode == .locate, locateState == .ready,
              now - lastLiveReadyT <= CoachConst.locateConfirmLatchS + 0.5,
              let a = capturedAnchors, let press = capturedPress,
              let off = PointCalibration.offset(press: press, affine: a.affine, hand: a.hand,
                                                aspect: frameAspect) else { return false }
        calibration.set(off, for: point.id)
        endLocate()
        return true
    }

    // Leave the locate step (confirmed or skipped) and start coaching clean. The guide ring may
    // jump to the newly saved spot — reset the filters so it snaps rather than lerps there.
    func endLocate() {
        guard mode == .locate else { return }
        mode = .coach
        machine.reset()
        smootherReset()
        resetLocateTracking()   // one canonical teardown — no stale anchors survive into coach mode
        overlay.pressTip = nil
        overlay.progress = 0
    }

    // Re-enter the guided locate step from coaching (the "re-find the spot" affordance — without
    // it, a bad confirm was only fixable by ending the whole session; review-caught). Banked
    // rounds are kept; the CURRENT round's un-banked hold is honestly dropped (explicit user
    // choice). Phase resets to .noHand so phase-keyed observers (rest-gap Vision idling, voice)
    // don't stay latched to a stale coach phase while locating.
    func beginLocate() {
        guard mode == .coach, !sessionComplete else { return }
        mode = .locate
        restLeft = nil
        machine.reset()
        smootherReset()
        resetLocateTracking()
        overlay.pressTip = nil
        overlay.progress = 0
        if phase != .noHand { phase = .noHand }
    }

    // A pause/app-switch stops camera frames, and the confirm latch is frame-clocked — void the
    // offer so a stale press can't sit confirmable behind the pause overlay (review-caught).
    func suspendLocate() {
        guard mode == .locate else { return }
        locateWindow.removeAll()
        if locateCandidate != nil { overlay.locateCandidate = nil }
        if locateState == .ready || locateState == .settling { locateState = .noPress }
        lastLiveReadyT = -.infinity
        latchLapsed = false
        chirBlockedSince = nil
    }

    // `point` is nil only for the flip-time refresh (no acupoint in reach there — the generic
    // flip line covers it); `now` drives the chirality-blocked honesty timer.
    private func locateCue(_ s: LocateState, point: Acupoint?, now: Double) -> String {
        switch s {
        case .noHand:
            return selfCoaching
                ? AppLocale.pick("把手放到镜头前，先一起找到这个点。",
                                 "Bring your hand into view — let's find the spot first.")
                : AppLocale.pick("把对方要按的手放进画面，先一起找到这个点。",
                                 "Bring their hand into view — let's find the spot first.")
        case .wrongFace:
            if let point { return faceCue(point) }
            return AppLocale.pick("翻一下手，换一面对着镜头。", "Turn the hand over to face the camera.")
        case .noPress:
            if latchLapsed {
                return AppLocale.pick("刚才的确认超时了 — 再按住那个点一下，然后点「就是这里」。",
                                      "The offer timed out — press your spot again briefly, then tap \"This is my spot\".")
            }
            return selfCoaching
                ? AppLocale.pick("对照说明，用另一只手的指尖在虚线圈附近轻轻按找。",
                                 "Follow the guide — feel around the dashed ring with your other fingertip.")
                : AppLocale.pick("对照说明，用你的指尖在对方手上的虚线圈附近轻轻按找。",
                                 "Follow the guide — feel around the dashed ring on their hand with your fingertip.")
        case .offGuide:  return AppLocale.pick("有点远了 — 回到虚线圈附近再找找。",
                                               "A little far — feel around closer to the dashed ring.")
        case .settling:
            // A tight press blocked ONLY by unreadable handedness must not promise "hold still"
            // forever — after a couple seconds, say what's actually wrong and name the way out.
            if let since = chirBlockedSince, now - since > CoachConst.locateChirBlockedHintS {
                return AppLocale.pick("看不清这只手的方向 — 稍微调整角度，或点「先跳过」用标准位置。",
                                      "Couldn't read the hand clearly — adjust the angle a little, or Skip to use the standard spot.")
            }
            return AppLocale.pick("感觉对了就按住不动一小会儿。",
                                  "Feels right? Hold the press still for a moment.")
        case .ready:     return AppLocale.pick("就按在这里？点「就是这里」，我会记住你的位置。",
                                               "Pressing right there? Tap \"This is my spot\" and I'll remember it.")
        }
    }

    // Guarded writes: this runs every camera frame, and an unconditional @Published assignment
    // invalidates the SwiftUI overlay 30×/sec even when nothing changed.
    // Inputs the cue string is a pure function of — see apply().
    private var lastCuePhase: CoachPhase? = nil
    private var lastCueHasPresser: Bool? = nil

    private func apply(_ phase: CoachPhase, point: Acupoint, hasPresser: Bool) {
        if self.phase != phase { self.phase = phase }
        let p = machine.progress
        if progress != p { overlay.progress = p }
        // The cue only depends on (phase, hasPresser) for a fixed point, so BUILD it only when one of
        // those moves. It used to be constructed unconditionally and then discarded by the equality
        // check on the next line — a String allocation (and, in .resting, an interpolation) every
        // camera frame, which is precisely what the comment above this function was trying to avoid.
        if phase != lastCuePhase || hasPresser != lastCueHasPresser {
            lastCuePhase = phase; lastCueHasPresser = hasPresser
            let newCue = cueFor(phase, point: point, hasPresser: hasPresser)
            if cue != newCue { cue = newCue }
        }
    }

    private func cueFor(_ phase: CoachPhase, point: Acupoint, hasPresser: Bool) -> String {
        switch phase {
        case .noHand:           return selfCoaching
            ? AppLocale.pick("把手放到镜头前就好。", "Bring your hand into view whenever you're ready.")
            : AppLocale.pick("把对方要按的手放进画面就好。", "Bring their hand into view whenever you're ready.")
        case .wrongFace:        return faceCue(point)
        case .searching:        return hasPresser ? alignCue(point)
                                    : selfCoaching
                                        ? AppLocale.pick("另一只手的指尖慢慢移过来，两只手都留在画面里。",
                                                         "Ease your other fingertip over — keep both hands in view.")
                                        : AppLocale.pick("你的指尖慢慢移过来，对方的手留在画面里。",
                                                         "Ease your fingertip over — keep their hand in view.")
        case .onTargetUnstable: return AppLocale.pick("就是这里 — 轻轻稳住。", "That's the spot — settle in gently.")
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
                                 "Turn the outer side of the forearm — the back-of-hand side — toward the camera.")
                : AppLocale.pick("手掌向上，让前臂内侧朝向相机。",
                                 "Turn the palm up so the inner side of the forearm faces the camera.")
        }
        if !selfCoaching {
            return p.requiresDorsal
                ? AppLocale.pick("把对方的手翻过来，手背对着镜头。", "Turn their hand over so the back faces the camera.")
                : AppLocale.pick("把对方的手翻过来，手心对着镜头。", "Turn their hand over so the palm faces the camera.")
        }
        return p.requiresDorsal
            ? AppLocale.pick("翻一下手，让手背对着镜头。", "Turn your hand over so the back faces the camera.")
            : AppLocale.pick("翻一下手，让手心对着镜头。", "Turn your hand over so the palm faces the camera.")
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
            ? AppLocale.pick("手背对着镜头，让指尖轻轻找到圆圈。", "Back of the hand to the camera — let your fingertip find the ring.")
            : AppLocale.pick("手心对着镜头，让指尖轻轻找到圆圈。", "Palm to the camera — let your fingertip find the ring.")
    }
    private func holdCue(_ p: Acupoint) -> String {
        if !p.coachHoldL.isEmpty { return p.coachHoldL }
        return AppLocale.pick("很好 — 稳稳按住，跟着呼吸，慢慢画小圈。",
                              "Good — keep it steady, breathe slow, small easy circles.")
    }

    // MARK: - Sticky role assignment

    private func roleReset() {
        lastReceiverWrist = nil; lastPresserWrist = nil; swapVotes = 0
        heldPresserFinger = nil
    }

    // Every fingertip considered as the pressing finger — ANY finger, not a fixed index (the user
    // may press with the thumb / middle / etc.). Index first so a genuine index press wins a tie.
    // (`Hand.pressTip` supplies the DIP/PIP reconstruction for .indexTip when the tip is occluded.)
    private static let pressFingers: [HandJoint] = [.indexTip, .middleTip, .thumbTip, .ringTip, .pinkyTip]

    // The pressing fingertip = the fingertip of a NON-receiver hand nearest the ring, within
    // `acquireRadius`. This is the user-directed rewrite of presser detection: the massaging hand can
    // never be the hand the acupoint sits on (receiver excluded by wrist identity), and only a tip
    // that comes into PROXIMITY of the point counts — the receiver's own fingers and anything hovering
    // far away are voided. The chosen identity is HELD across frames so the dot doesn't flicker; a
    // genuine identity change is reported so the caller can reset the tip smoother (no cross-finger lerp).
    private func selectPresserTip(hands: [Hand], receiverWrist: CGPoint?,
                                  ringCenter: CGPoint, acquireRadius: CGFloat)
            -> (point: CGPoint, confidence: Float, changed: Bool)? {
        struct Cand { let finger: HandJoint; let point: CGPoint; let conf: Float; let d: CGFloat }
        var cands: [Cand] = []
        for h in hands {
            // Exclude the receiving hand — its own fingertips must never be read as the presser.
            if let rw = receiverWrist, let w = h.p(.wrist), w == rw { continue }
            for finger in Self.pressFingers {
                guard let m = h.pressTip(finger) else { continue }
                cands.append(Cand(finger: finger, point: m.point, conf: m.confidence, d: isoDist(m.point, ringCenter)))
            }
        }
        // The nearest fingertip within the acquire radius is a fresh candidate. The currently-held
        // finger keeps its slot within a LARGER keep radius (exit-band hysteresis), so a one-frame
        // boundary wobble or a near-tie doesn't drop it and flip identity. Only switch to a fresh
        // finger that is clearly closer (beyond the hold margin) — that's a real change of press.
        let keepRadius = acquireRadius * CoachConst.exitRadiusMult
        let fresh = cands.filter { $0.d <= acquireRadius }.min(by: { $0.d < $1.d })
        let held = heldPresserFinger.flatMap { hf in cands.first { $0.finger == hf && $0.d <= keepRadius } }
        let chosen: Cand?
        if let held, let fresh {
            chosen = held.d <= fresh.d + CoachConst.presserHoldMargin ? held : fresh
        } else {
            chosen = held ?? fresh
        }
        // No candidate this frame: return nil but KEEP heldPresserFinger, so a re-acquire of the same
        // finger after a within-grace dropout is not misread as a switch (which would reset the smoother
        // and lerp the dot across the gap; the caller's grace/gone branches govern the dot itself).
        guard let c = chosen else { return nil }
        let changed = heldPresserFinger != nil && c.finger != heldPresserFinger
        heldPresserFinger = c.finger
        return (c.point, c.conf, changed)
    }

    private func assignRoles(_ hands: [Hand], target: MediaPipeTarget, requiresDorsal: Bool) -> (Hand?, Hand?) {
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
               isoDist(w, lpw) < isoDist(w, lrw) {
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
        // OTHER hand's press tip (the original choice — the score tiebreak below).
        func score(_ recv: Hand, _ other: Hand) -> CGFloat {
            guard let t = recv.weightedTarget(target.anchors),
                  let tip = other.pressTip(target.pressFinger)?.point else { return .greatestFiniteMagnitude }
            return isoDist(t, tip)
        }
        let sA = score(a, b), sB = score(b, a)
        // PRIMARY signal: the receiver is the hand whose FACE matches the point (dorsal for TE3). The
        // massaging hand reaches in fingers-first and does NOT pass the face gate, so this separates the
        // two robustly — unlike the symmetric nearest-target score, which oscillates when the hands
        // overlap and flips the ring onto the massaging hand (worst on the two-person BACK camera,
        // user-reported). Fall back to the score only when the face gate can't tell them apart (both or
        // neither match, or a face is momentarily unreadable — isDorsal nil).
        let faceA = a.isDorsal.map { $0 == requiresDorsal }
        let faceB = b.isDorsal.map { $0 == requiresDorsal }
        let prefAIsReceiver: Bool
        if faceA == true, faceB != true { prefAIsReceiver = true }
        else if faceB == true, faceA != true { prefAIsReceiver = false }
        else { prefAIsReceiver = sA <= sB }

        // Match the two current hands to the previous roles by wrist proximity (Vision
        // does not give stable IDs across frames), then only flip on sustained disagreement.
        if let lrw = lastReceiverWrist, let lpw = lastPresserWrist,
           let aw = a.p(.wrist), let bw = b.p(.wrist) {
            let cost1 = isoDist(aw, lrw) + isoDist(bw, lpw)   // a=receiver, b=presser
            let cost2 = isoDist(bw, lrw) + isoDist(aw, lpw)   // b=receiver, a=presser
            let stickyAIsReceiver = cost1 <= cost2

            // ROLE LOCK while engaged on the point (on-target / holding / pause-grace): mid-press the
            // two hands overlap so much that the nearest-target preference oscillates — on the forearm
            // points (PC6/SJ5, target extrapolated past the wrist) it repeatedly flipped the ring onto
            // the MASSAGING hand. Nobody swaps hands mid-press: while engaged, keep the sticky roles
            // and don't accumulate swap votes. Swaps confirm only while genuinely searching.
            // A settling/ready locate press is the same situation — the user is mid-press, feeling
            // for the spot — so it locks roles too.
            let engaged = machine.isEngaged || phase == .paused ||
                (mode == .locate && (locateState == .settling || locateState == .ready))
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
                smootherReset()
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
