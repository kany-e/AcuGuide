import Foundation
import CoreGraphics
import Vision

// Per-user spot correction, learned from the on-camera guided locate step. Anatomy varies between
// people, so the anchor-weighted target can sit a little off for a given user; when they find the
// spot BY FEEL and confirm the press, the delta between their press and the computed target is
// stored here and applied to every future ring. The offset lives in a canonical hand frame
// (origin middleMCP, scale |middleMCP−wrist|, rotation wrist→middleMCP = +Y, chirality folded),
// so one stored correction re-applies correctly at any hand position, rotation, distance, or
// side. It is a SLIGHT correction by design: the magnitude is clamped so a stray capture can
// never drag the ring onto different anatomy (safety rule — the guide stays a guide).
//
// COORDINATES ARE ISOTROPIC (width units): landmarks arrive normalized PER AXIS (x/W, y/H), and a
// physical hand rotation is NOT a similarity transform in that anisotropic space — a frame built
// on raw coords re-applied an offset captured upright at up to (H/W)² ≈ 3.2× the physical
// distance once the hand lay sideways (review-caught, the same trap isoDist fixed in the engine).
// So every point is converted to width units (y ÷ aspect) before the CanonicalFrame is built and
// converted back after. This also puts the stored norm in the SAME units as the engine's capture
// gate (isoDist/isoHandSize). ShadowLocalizer keeps its own RAW anisotropic frame — that one must
// stay bit-compatible with train.py.
final class PointCalibration: ObservableObject {
    static let shared = PointCalibration()

    struct Offset: Codable, Equatable {
        var dx: Double   // canonical hand-frame units (1.0 = wrist→middleMCP length, isotropic)
        var dy: Double
        var norm: Double { (dx * dx + dy * dy).squareRoot() }
    }

    // The clamp: how far a user's confirmed press may pull the ring, in iso hand-size units. It
    // MUST track the locate step's OUTER capture radius — a press the gate accepted must never be
    // silently truncated on save, which would move the user's spot somewhere they never pressed.
    // (Kept in step with CoachConst.locateFarCaptureRadiusXHandSize; CalibrationTests pins the
    // relationship so the two can't drift apart.)
    //
    // The value widened with the gate: 0.30 blocked users whose point genuinely isn't where the
    // affine estimate puts it, which defeated the feature's whole purpose. A press on a completely
    // wrong landmark is still capped — it just caps further out, and the UI now says plainly when a
    // spot is unusually far from the standard location rather than refusing it.
    static let maxOffsetXHandSize = CoachConst.locateFarCaptureRadiusXHandSize

    @Published private(set) var table: [String: Offset]
    private let defaults: UserDefaults
    // v2: offsets are stored in ISOTROPIC canonical units (v1 was raw-anisotropic — different
    // semantics, so old blobs are simply ignored rather than misread).
    private static let key = "pointCalibration.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            if let t = try? JSONDecoder().decode([String: Offset].self, from: data) {
                // Re-clamp on LOAD, not just on set(): a restored backup, synced defaults, or a
                // blob written by a build with a looser clamp must never apply un-clamped — the
                // safety rule is "a correction can never drag the ring onto different anatomy",
                // and only set() enforced it before (review-caught).
                table = t.mapValues(Self.clamped)
            } else {
                // Never destroy what we can't read: park the blob under a side key (the
                // PracticeStore precedent) so a future build can recover it, and start empty —
                // the next persist() would otherwise overwrite the user's confirmed spots.
                defaults.set(data, forKey: Self.key + ".unreadable")
                table = [:]
            }
        } else {
            table = [:]
        }
    }

    func offset(for id: String) -> Offset? { table[id] }
    func hasCalibration(_ id: String) -> Bool { table[id] != nil }

    // The one clamp rule (shared by set() and the load path): magnitude capped, direction kept.
    private static func clamped(_ o: Offset) -> Offset {
        let n = o.norm
        guard n > maxOffsetXHandSize, n > 0 else { return o }
        let s = maxOffsetXHandSize / n
        return Offset(dx: o.dx * s, dy: o.dy * s)
    }

    // Store a correction, clamped to maxOffsetXHandSize (direction preserved).
    func set(_ o: Offset, for id: String) {
        table[id] = Self.clamped(o)
        persist()
    }

    func clear(_ id: String) {
        guard table[id] != nil else { return }
        table[id] = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(table) { defaults.set(data, forKey: Self.key) }
    }

    // MARK: - Canonical-frame plumbing

    // Raw per-axis-normalized point ⇄ isotropic width units (aspect = frame W/H, <1 in portrait).
    private static func iso(_ p: CGPoint, _ aspect: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: p.y / aspect)
    }
    private static func raw(_ p: CGPoint, _ aspect: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: p.y * aspect)
    }

    // Parity-aware canonical frame over ISO points. The fold convention was tuned in the MIRRORED
    // (selfie-preview) parity — under the back camera's un-mirrored coordinates the same physical
    // hand has flipped x-parity, so the fold must flip with it or a stored dx lands on the wrong
    // (radial/ulnar) side. `(right == mirrored)` maps both parities onto the mirrored-convention
    // fold. Chirality .unknown returns NIL: the fold direction would be a guess, and a wrong
    // guess mirrors the correction across the hand — a calibration must never be captured or
    // applied on a frame whose handedness Vision couldn't read.
    static func canonicalFrame(_ hand: Hand, aspect: CGFloat) -> CanonicalFrame? {
        guard hand.chirality != .unknown, aspect > 0 else { return nil }
        let foldAsRight = (hand.chirality == .right) == hand.mirroredCoords
        return CanonicalFrame(hand.points.mapValues { iso($0, aspect) }, isRight: foldAsRight)
    }

    // The correction a confirmed press implies: canonical(press) − canonical(affine target).
    // nil when the hand can't build a frame (wrist/middleMCP missing, or unknown chirality).
    static func offset(press: CGPoint, affine: CGPoint, hand: Hand, aspect: CGFloat) -> Offset? {
        guard let cf = canonicalFrame(hand, aspect: aspect) else { return nil }
        let p = cf.to(iso(press, aspect)), a = cf.to(iso(affine, aspect))
        return Offset(dx: p.0 - a.0, dy: p.1 - a.1)
    }

    // Apply the stored correction (if any) to this frame's affine target, through the hand's
    // current canonical frame — the offset rides the hand's pose. Falls back to the affine
    // target untouched when there is no stored offset or no buildable frame (including unknown
    // chirality — better no correction for a frame than a mirror-flipped one).
    func apply(_ affine: CGPoint, hand: Hand, pointId: String, aspect: CGFloat) -> CGPoint {
        guard let off = table[pointId], let cf = Self.canonicalFrame(hand, aspect: aspect) else { return affine }
        let a = cf.to(Self.iso(affine, aspect))
        return Self.raw(cf.from(a.0 + off.dx, a.1 + off.dy), aspect)
    }

    // Single-point canonical round-trip, used by the locate step to keep the latched "your press"
    // marker riding the LIVE hand for display (the confirm math itself uses the frozen snapshot).
    static func canonical(_ p: CGPoint, hand: Hand, aspect: CGFloat) -> (x: Double, y: Double)? {
        guard let cf = canonicalFrame(hand, aspect: aspect) else { return nil }
        let q = cf.to(iso(p, aspect))
        return (q.0, q.1)
    }
    static func reproject(_ q: (x: Double, y: Double), hand: Hand, aspect: CGFloat) -> CGPoint? {
        guard let cf = canonicalFrame(hand, aspect: aspect) else { return nil }
        return raw(cf.from(q.x, q.y), aspect)
    }
}
