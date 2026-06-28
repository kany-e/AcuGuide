import CoreHaptics
import UIKit

// Coaching haptics — a light tick when the pressing finger first enters the target, and a
// success pattern at COMPLETE. CoreHaptics where available, UIFeedbackGenerator as the fallback.
// Driven off phase TRANSITIONS (already debounced), so there is no per-frame buzzing and no
// haptics during WRONG_FACE / NO_HAND spam.
final class CoachHaptics: ObservableObject {
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    init() {
        if supportsHaptics {
            engine = try? CHHapticEngine()
            // Restart the engine if the system stops/resets it (interruptions, backgrounding).
            engine?.stoppedHandler = { [weak self] _ in try? self?.engine?.start() }
            engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
            try? engine?.start()
        } else {
            impact.prepare()
            notify.prepare()
        }
    }

    // Light single tick — finger first entered the target zone.
    func enterTick() {
        guard supportsHaptics, let engine else { impact.impactOccurred(intensity: 0.6); return }
        play([transient(at: 0, intensity: 0.5, sharpness: 0.5)], on: engine)
    }

    // Success pattern — routine complete.
    func complete() {
        guard supportsHaptics, let engine else { notify.notificationOccurred(.success); return }
        play([transient(at: 0, intensity: 0.6, sharpness: 0.4),
              transient(at: 0.12, intensity: 1.0, sharpness: 0.6)], on: engine)
    }

    private func transient(at t: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private func play(_ events: [CHHapticEvent], on engine: CHHapticEngine) {
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
