import Foundation
import CoreGraphics
import Vision

// Per-user spot correction, learned from the on-camera guided locate step. Anatomy varies between
// people, so the anchor-weighted target can sit a little off for a given user; when they find the
// spot BY FEEL and confirm the press, the delta between their press and the computed target is
// stored here and applied to every future ring. The offset lives in the CANONICAL HAND FRAME
// (CanonicalFrame — origin middleMCP, scale |middleMCP−wrist|, rotation wrist→middleMCP = +Y,
// chirality folded), so one stored correction re-applies correctly at any hand position, rotation,
// distance, or side. It is a SLIGHT correction by design: the magnitude is clamped so a stray
// capture can never drag the ring onto different anatomy (safety rule — the guide stays a guide).
final class PointCalibration: ObservableObject {
    static let shared = PointCalibration()

    struct Offset: Codable, Equatable {
        var dx: Double   // canonical hand-frame units (1.0 = wrist→middleMCP length)
        var dy: Double
        var norm: Double { (dx * dx + dy * dy).squareRoot() }
    }

    // The clamp: how far a user's confirmed press may pull the ring, in hand-size units. The
    // coached tolerances are 0.16–0.24, so 0.30 allows a real anatomical fine-tune (~a finger
    // width) while a press on the wrong landmark stays capped near the standard spot.
    static let maxOffsetXHandSize = 0.30

    @Published private(set) var table: [String: Offset]
    private let defaults: UserDefaults
    private static let key = "pointCalibration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let t = try? JSONDecoder().decode([String: Offset].self, from: data) {
            table = t
        } else {
            table = [:]
        }
    }

    func offset(for id: String) -> Offset? { table[id] }
    func hasCalibration(_ id: String) -> Bool { table[id] != nil }

    // Store a correction, clamped to maxOffsetXHandSize (direction preserved).
    func set(_ o: Offset, for id: String) {
        var c = o
        let n = o.norm
        if n > Self.maxOffsetXHandSize, n > 0 {
            let s = Self.maxOffsetXHandSize / n
            c = Offset(dx: o.dx * s, dy: o.dy * s)
        }
        table[id] = c
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

    // Parity-aware canonical frame. CanonicalFrame's fold flag was tuned in the MIRRORED
    // (selfie-preview) convention — under the back camera's un-mirrored coordinates the same
    // physical hand has flipped x-parity, so the fold must flip with it or a stored dx lands on
    // the wrong (radial/ulnar) side of the point. `(right == mirrored)` maps both parities onto
    // the mirrored-convention fold. (ShadowLocalizer keeps its own raw call — its head was
    // TRAINED in the mirrored convention and must stay bit-compatible with train.py.)
    static func canonicalFrame(_ hand: Hand) -> CanonicalFrame? {
        let foldAsRight = (hand.chirality == .right) == hand.mirroredCoords
        return CanonicalFrame(hand.points, isRight: foldAsRight)
    }

    // The correction a confirmed press implies: canonical(press) − canonical(affine target).
    // nil when the hand can't build a frame (wrist/middleMCP missing).
    static func offset(press: CGPoint, affine: CGPoint, hand: Hand) -> Offset? {
        guard let cf = canonicalFrame(hand) else { return nil }
        let p = cf.to(press), a = cf.to(affine)
        return Offset(dx: p.0 - a.0, dy: p.1 - a.1)
    }

    // Apply the stored correction (if any) to this frame's affine target, through the hand's
    // current canonical frame — the offset rides the hand's pose. Falls back to the affine
    // target untouched when there is no stored offset or no buildable frame.
    func apply(_ affine: CGPoint, hand: Hand, pointId: String) -> CGPoint {
        guard let off = table[pointId], let cf = Self.canonicalFrame(hand) else { return affine }
        let a = cf.to(affine)
        return cf.from(a.0 + off.dx, a.1 + off.dy)
    }
}
