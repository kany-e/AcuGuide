import Foundation
import MetricKit

// Crash/hang visibility WITHOUT telemetry: MetricKit diagnostics are delivered by the OS, written
// as JSON to the app's own Documents/diagnostics/ folder, and never leave the device — the user
// (or a debugging session) can read them via the Files app. Keeps the "no analytics, no servers"
// posture while ending the current total blindness to field crashes.
final class Diagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = Diagnostics()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        for (i, payload) in payloads.enumerated() {
            let url = dir.appendingPathComponent("diagnostic-\(stamp)-\(i).json")
            try? payload.jsonRepresentation().write(to: url)
        }
    }

    // Metric payloads (battery/launch statistics) are not collected — diagnostics only.
    func didReceive(_ payloads: [MXMetricPayload]) {}
}
