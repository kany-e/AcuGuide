import AVFoundation
import Vision
import SwiftUI

// Owns the capture session + Vision hand-pose pipeline and drives a CoachEngine.
// Native equivalent of the web app's useMediaPipe + useHandClassifier.
final class CameraCoach: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let engine: CoachEngine
    var acupoint: Acupoint

    // Portrait display aspect (width/height, <1) of the camera frame, published so the overlay can
    // map normalized landmarks through the SAME aspect-fill crop the preview uses (otherwise the
    // ring/press dot are offset+scaled from the visible video). Defaults to 9:16.
    @Published var frameAspect: CGFloat = 9.0 / 16.0
    private var lastAspect: CGFloat = 0

    // Camera position. Front (default) = coach yourself in the mirrored selfie preview.
    // Back = point the phone at ANOTHER person's hand (two-person use: one holds and presses,
    // the camera watches the receiver) — un-mirrored, like any rear-camera view.
    @Published private(set) var usingFront = true

    // Dim-scene flag for the "why can't it see my hand" hint. Sampled from the luma plane every
    // ~15th frame (a sparse grid, not the full image), with hysteresis so it never flickers.
    @Published private(set) var lowLight = false
    private var lumaFrameCount = 0
    private var lastLowLight = false

    // Bumped on the main thread AFTER a flip's session reconfigure commits. The preview layer's
    // connection is RECREATED by the reconfigure — after SwiftUI already re-rendered for the
    // usingFront change — so without this second render pass the fresh connection never gets its
    // portrait rotation re-applied and the view comes up upside down (user-reported).
    @Published private(set) var configGeneration = 0

    // SINGLE SOURCE OF TRUTH for mirroring. `mirrored` (main thread) drives the preview
    // connection; `queueMirrored` is the capture-queue-confined copy that drives the landmark
    // x-flip — so the flag is never read across threads (no data race). Flipping the debug
    // toggle updates the queue copy and resets the One-Euro smoother (negating every landmark
    // x is a full-frame coordinate jump that would otherwise spike the filter's velocity).
    @Published var mirrorFlip = false {
        didSet {
            let m = mirrored
            mainSceneGen += 1
            let gen = mainSceneGen
            queue.async { [weak self] in self?.queueMirrored = m; self?.queueSceneGen = gen }
            // Same parity discontinuity as a camera flip: every landmark x becomes 1−x, so the
            // engine must drop EVERYTHING keyed to the old parity — including the guided-locate
            // window/candidate/anchors (a mid-locate toggle mixed parities into one centroid and
            // could persist a wrong-direction calibration; review-caught). smootherReset alone
            // was not enough.
            engine.cameraFlipped()
        }
    }
    var mirrored: Bool { usingFront != mirrorFlip }   // XOR — main thread / preview
    private var queueMirrored = true                  // capture queue only
    // Camera position, queue-confined copy (configureIfNeeded runs on the queue and must not read
    // the main-published `usingFront` — a data race, review-caught).
    private var queuePosition: AVCaptureDevice.Position = .front

    // Scene generation: bumped on main for every parity/scene change (flip, mirror toggle) and
    // echoed to the queue copy AFTER the change lands there. Frames captured under an old parity
    // carry the old generation and are dropped before reaching the freshly-reset engine — closing
    // the stale-parity window between engine.cameraFlipped() and the queue's reconfigure.
    private var mainSceneGen = 0                      // main thread only
    private var queueSceneGen = 0                     // capture queue only

    private let queue = DispatchQueue(label: "camera.coach")
    // Inverted-pass backoff bookkeeping (capture queue only): after 12 consecutive weak-triggered
    // passes that produced no upgrade, drop to every 3rd frame until one does.
    private var invertedTick = 0
    private var invertedNoUpgradeStreak = 0
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    // Second-chance pass for INVERTED hands: Vision's hand model is weak on fingers-down /
    // tips-away hands (the massaging hand reaching in from the top of frame — user-reported as
    // undetectable). When the primary pass finds fewer than two hands, the frame is re-run
    // rotated 180° (where an inverted hand looks upright) and results fold back. Separate request
    // instance so the two passes' results don't overwrite each other.
    private let invertedRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private var videoConnection: AVCaptureConnection?

    init(engine: CoachEngine, acupoint: Acupoint) {
        self.engine = engine
        self.acupoint = acupoint
        super.init()
        queueMirrored = mirrored
        // NOTE: session configuration is DEFERRED to start() — creating an AVCaptureDeviceInput is
        // what makes iOS present the camera-permission alert, and this object is built when the
        // coach view appears, BEFORE CameraGate has shown its in-context explainer. Configuring
        // here fired the system dialog cold over the safety gate.
    }

    // Queue-confined. Configure lazily, and only once authorized — CameraGate guarantees start()
    // is only reached in the authorized state, so the permission prompt always follows the explainer.
    private var configured = false
    private func configureIfNeeded() {
        guard !configured, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        installInput(position: queuePosition)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video) {
            videoConnection = conn
            // Deliver portrait-upright buffers so landmark coords share the portrait overlay's
            // normalized space (the app is portrait-locked). Data output stays UN-mirrored; the
            // PREVIEW does the mirroring and buildHand flips landmark x to match.
            conn.forcePortrait()
            conn.setMirrored(false)
        }
        session.commitConfiguration()
    }

    // Queue-confined. Validate the replacement BEFORE touching the session's inputs, so a missing/
    // unavailable camera never commits an input-less session. Shared by configure + flip.
    @discardableResult
    private func installInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }

    // Derive the Vision orientation from the capture connection (NOT a hardcoded `.up`),
    // handling the iOS 16 (`videoOrientation`) vs iOS 17+ (`videoRotationAngle`) API split.
    // The connection is configured portrait + un-mirrored, so the upright orientation is `.up`;
    // we still confirm it from the connection so a platform that ignored the portrait request is
    // rotated correctly rather than silently wrong.
    private func visionOrientation() -> CGImagePropertyOrientation {
        guard let conn = videoConnection else { return .up }
        if #available(iOS 17.0, *) {
            switch Int(conn.videoRotationAngle.rounded()) {
            case 90:  return .up      // portrait (configured)
            case 0:   return .right   // sensor-native landscape, not rotated
            case 180: return .left
            case 270: return .down
            default:  return .up
            }
        } else {
            switch conn.videoOrientation {
            case .portrait:           return .up      // configured
            case .landscapeRight:     return .right   // not rotated to portrait
            case .landscapeLeft:      return .left
            case .portraitUpsideDown: return .down
            @unknown default:         return .up
            }
        }
    }

    func start() {
        queue.async {
            self.configureIfNeeded()   // deferred from init: runs only once authorized (via CameraGate)
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
    func stop()  {
        ShadowLocalizer.shared.logSummary()   // dump the session's per-point/regime shadow telemetry
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    // Flip front ⇄ back (two-person mode). Reconfigures the session on the capture queue; the
    // mirroring convention updates atomically with it (front = mirrored selfie, back = un-mirrored),
    // and the engine drops EVERYTHING keyed to the old coordinate space/scene (smoothers, sticky
    // role anchors, face verdict, stale ring/tip) — a flip is a new scene, not a wobble.
    func flipCamera() {
        usingFront.toggle()
        let pos: AVCaptureDevice.Position = usingFront ? .front : .back
        let m = mirrored
        mainSceneGen += 1
        let gen = mainSceneGen
        engine.cameraFlipped()
        queue.async { [weak self] in
            guard let self else { return }
            self.queueMirrored = m
            self.queuePosition = pos
            guard self.configured else { self.queueSceneGen = gen; return }   // never authorized/configured → nothing to swap yet
            self.session.beginConfiguration()
            // installInput validates the replacement BEFORE removing the old input; on failure
            // (Simulator, camera in use) the session keeps its previous input and we revert the
            // published state so the UI doesn't report a camera that never installed.
            if !self.installInput(position: pos) {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.usingFront.toggle(); self.engine.cameraFlipped()
                    self.mainSceneGen += 1
                    let genBack = self.mainSceneGen
                    let mBack = self.mirrored
                    let posBack: AVCaptureDevice.Position = self.usingFront ? .front : .back
                    self.queue.async {
                        self.queueMirrored = mBack; self.queuePosition = posBack
                        self.queueSceneGen = genBack
                    }
                }
                return
            }
            if let conn = self.session.outputs.compactMap({ $0.connection(with: .video) }).first {
                self.videoConnection = conn
                conn.forcePortrait()
                conn.setMirrored(false)   // data output stays un-mirrored; the PREVIEW mirrors
            }
            self.session.commitConfiguration()
            self.queueSceneGen = gen      // frames from here on carry the new scene's parity
            // Second render pass so CameraPreview re-applies portrait+mirroring to the connection
            // that was just recreated (see configGeneration).
            DispatchQueue.main.async { self.configGeneration += 1 }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lumaFrameCount += 1
        if lumaFrameCount % 15 == 0 { updateLowLight(pixel) }
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel)
        let aspect = CGFloat(min(w, h)) / CGFloat(max(w, h))   // portrait display aspect (W/H)
        if abs(aspect - lastAspect) > 0.001 {
            lastAspect = aspect
            DispatchQueue.main.async { self.frameAspect = aspect }
        }
        let orientation = visionOrientation()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation, options: [:])
        try? handler.perform([request])
        var hands = (request.results ?? []).compactMap { buildHand($0) }

        // Inverted-hand second chance (see invertedRequest): when the primary pass came up short
        // OR any hand it found is WEAK — the top-down/tips-away massaging hand often flickers
        // through the weak tier in the primary pass while the rotated pass reads it cleanly, so
        // the weak read deserves the second opinion too (user-reported: top-down presser very
        // shaky). Duplicates (a hand Vision found BOTH ways) keep the BETTER read: primary wins
        // unless the inverted read is clearly more confident — the bias stops the source (and its
        // slightly different landmark geometry) from alternating frame-to-frame, itself a jitter
        // source. The weak-triggered run BACKS OFF after a streak of no-upgrade passes (a second
        // full Vision inference per frame is real cost during whole press sessions) and resumes
        // full rate the moment a pass earns its keep.
        invertedTick &+= 1
        let missingHand = hands.count < 2
        let weakThrottled = invertedNoUpgradeStreak >= 12 && invertedTick % 3 != 0
        if missingHand || (hands.contains(where: { $0.weak }) && !weakThrottled) {
            let flipped = VNImageRequestHandler(cvPixelBuffer: pixel,
                                                orientation: Self.rotated180(orientation), options: [:])
            try? flipped.perform([invertedRequest])
            var upgraded = false
            for obs in invertedRequest.results ?? [] {
                guard let h = buildHand(obs, rotated180: true) else { continue }
                // Duplicate = SAME physical hand seen by both passes. A 180° rotation preserves
                // chirality, so the true duplicate must match handedness — and among matches take
                // the NEAREST wrist, not the first within range: mid-press the two hands' wrists
                // can BOTH sit within the radius, and first-match let a confident inverted read
                // of the massaging hand REPLACE the receiver's entry (review-caught: the same
                // physical hand twice in the array, no receiver, ring crowned onto the presser).
                var best: (i: Int, d: CGFloat)? = nil
                if let b = h.p(.wrist) {
                    for (i, existing) in hands.enumerated() {
                        guard existing.chirality == h.chirality
                                || existing.chirality == .unknown || h.chirality == .unknown,
                              let a = existing.p(.wrist) else { continue }
                        let d = dist(a, b)
                        if d < 0.15, d < (best?.d ?? .greatestFiniteMagnitude) { best = (i, d) }
                    }
                }
                if let match = best {
                    if h.detectionConfidence > hands[match.i].detectionConfidence + 0.1 {
                        hands[match.i] = h
                        upgraded = true
                    }
                } else if hands.count < 2 {
                    hands.append(h)
                    upgraded = true
                }
            }
            // Streak accounting only for the weak-triggered case — a missing hand always retries.
            if !missingHand { invertedNoUpgradeStreak = upgraded ? 0 : invertedNoUpgradeStreak + 1 }
            else { invertedNoUpgradeStreak = 0 }
        }

        // Strong (receiver-eligible) hands first — the engine reads at most two, and a weak
        // presser candidate must never displace a full detection.
        hands.sort { !$0.weak && $1.weak }

        let now = CACurrentMediaTime()
        let gen = queueSceneGen
        DispatchQueue.main.async {
            // Drop frames captured under a previous scene's parity (mid-flip window): the engine
            // was already reset for the NEW scene and must not ingest old-parity hands.
            guard gen == self.mainSceneGen else { return }
            self.engine.frameAspect = aspect   // keeps the isotropic hit-test in step with the frame
            self.engine.update(hands: hands, point: self.acupoint, now: now)
        }
    }

    // Mean of a sparse luma-plane grid (every 32nd pixel), queue-confined. Thresholds are asymmetric
    // (enter dim < 55, leave dim > 70; video-range black is 16) so borderline scenes don't flicker
    // the hint. Non-4:2:0 formats (never seen from this output config) simply skip the check.
    private func updateLowLight(_ pixel: CVPixelBuffer) {
        let fmt = CVPixelBufferGetPixelFormatType(pixel)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
              fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixel, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixel, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixel, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, n = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w { sum += Int(ptr[y * rowBytes + x]); n += 1; x += 32 }
            y += 32
        }
        guard n > 0 else { return }
        let mean = Double(sum) / Double(n)
        let low = lastLowLight ? mean < 70 : mean < 55
        if low != lastLowLight {
            lastLowLight = low
            DispatchQueue.main.async { self.lowLight = low }
        }
    }

    // 180°-rotated counterpart of a Vision orientation (two mirrors = rotation; parity preserved).
    private static func rotated180(_ o: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .down;           case .down: return .up
        case .left: return .right;        case .right: return .left
        case .upMirrored: return .downMirrored;   case .downMirrored: return .upMirrored
        case .leftMirrored: return .rightMirrored; case .rightMirrored: return .leftMirrored
        }
    }

    private func buildHand(_ obs: VNHumanHandPoseObservation, rotated180: Bool = false) -> Hand? {
        // TWO-TIER acceptance. ≥0.5 (engine.js MIN_CONFIDENCE) = full hand, receiver-eligible —
        // matches the validated fixture path. 0.3–0.5 = WEAK tier, presser-only: a foreshortened /
        // tips-away massaging hand routinely scores here and used to be discarded outright, which
        // read as "the massaging hand cannot be detected at all" (user-reported). The engine never
        // lets a weak hand anchor the ring, and the palm-glaze gate still vets its tip.
        guard obs.confidence >= 0.3 else { return nil }
        // Shared converter (HandVision) → identical points to the M3 label harness (zero skew).
        // flipX = queueMirrored (capture-queue-confined; matches the mirrored preview);
        // rotated180 folds the inverted-pass coordinates back into the upright frame.
        guard let s = HandVision.sample(obs, flipX: queueMirrored, rotated180: rotated180) else { return nil }
        // mirroredCoords: isDorsal's sign convention needs the coordinate parity — chirality never
        // flips with our manual mirror, so back-camera (un-mirrored) frames negate the cross product.
        return Hand(points: s.points, chirality: obs.chirality, confidence: s.confidence,
                    mirroredCoords: queueMirrored,
                    weak: obs.confidence < Float(CoachConst.minConfidence),
                    detectionConfidence: obs.confidence)
    }
}

// Shared connection policy so the data output and the preview can't drift out of sync.
extension AVCaptureConnection {
    func setMirrored(_ on: Bool) {
        guard isVideoMirroringSupported else { return }
        automaticallyAdjustsVideoMirroring = false
        isVideoMirrored = on
    }
    func forcePortrait() {
        if #available(iOS 17.0, *) {
            if isVideoRotationAngleSupported(90) { videoRotationAngle = 90 }
        } else {
            if isVideoOrientationSupported { videoOrientation = .portrait }
        }
    }
}

// Live camera preview layer. `mirrored` is updated live (debug toggle) via updateUIView, and the
// preview connection is forced to the same portrait orientation as the data output so the video
// and the normalized landmark overlay share one coordinate space.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    var configGeneration = 0   // changes force updateUIView AFTER a flip's reconfigure (fresh connection)

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoLayer.session = session
        v.videoLayer.videoGravity = .resizeAspectFill
        apply(v)
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { apply(uiView) }

    private func apply(_ v: PreviewView) {
        guard let conn = v.videoLayer.connection else { return }
        conn.forcePortrait()
        conn.setMirrored(mirrored)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
