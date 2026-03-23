import Foundation
import os
import TelemetryDeck

private let analyticsLogger = Logger(subsystem: "com.typeless.app", category: "Analytics")

/// Lightweight wrapper around TelemetryDeck for privacy-first analytics.
///
/// Design principles:
/// - All numeric values are bucketed (e.g. "500-1000ms" not "743ms") to prevent re-identification
/// - Text content is NEVER sent
/// - Users can opt out via Settings toggle (UserDefaults "analyticsEnabled", default true)
/// - DEBUG builds are automatically tagged as test signals by TelemetryDeck
enum AnalyticsService {

    private static let appID = "6EB06114-0222-4BE1-9DDC-BB283B640436"

    /// Initialize TelemetryDeck. Call once from AppDelegate.applicationDidFinishLaunching.
    static func initialize() {
        guard isEnabled else {
            analyticsLogger.info("Analytics disabled by user preference")
            return
        }

        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        analyticsLogger.info("Analytics initialized (TelemetryDeck)")
    }

    /// Whether analytics is enabled (opt-out model: default true).
    static var isEnabled: Bool {
        // UserDefaults.standard.object returns nil for unset keys;
        // treat nil as true (opt-out default).
        if let value = UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool {
            return value
        }
        return true
    }

    /// Update enabled state and reinitialize if needed.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "analyticsEnabled")
        if enabled {
            let config = TelemetryDeck.Config(appID: appID)
            TelemetryDeck.initialize(config: config)
            analyticsLogger.info("Analytics re-enabled")
        }
        // TelemetryDeck doesn't have a teardown; disabled state is checked in track()
    }

    /// Track an analytics event with optional parameters.
    static func track(_ event: String, parameters: [String: String] = [:]) {
        guard isEnabled else { return }

        // Attach default parameters
        var params = parameters
        params["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        params["selectedEngine"] = UserDefaults.standard.string(forKey: "selectedASRModel") ?? "streamingParaformer"
        params["cloudRewriteEnabled"] = "\(!((UserDefaults.standard.string(forKey: "cloudRewriteAPIKey") ?? "").isEmpty) || GeneratedSecrets.cloudRewriteAPIKey != nil)"

        TelemetryDeck.signal(event, parameters: params)
    }

    // MARK: - Timing Helpers

    /// Convert a `ContinuousClock.Duration` to integer milliseconds.
    ///
    /// Usage:
    /// ```
    /// let start = ContinuousClock.now
    /// // ... work ...
    /// let ms = AnalyticsService.elapsedMs(since: start)
    /// ```
    static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: - Bucketing Helpers

    /// Map millisecond latency to a privacy-safe bucket string.
    static func latencyBucket(ms: Int) -> String {
        switch ms {
        case ..<500: return "0-500ms"
        case 500..<1000: return "500-1000ms"
        case 1000..<1500: return "1000-1500ms"
        case 1500..<2000: return "1500-2000ms"
        default: return "2000ms+"
        }
    }

    /// Fine-grained latency bucket for fast pipeline stages (TermNorm, ITN, etc.).
    static func fineLatencyBucket(ms: Int) -> String {
        switch ms {
        case ..<10: return "0-10ms"
        case 10..<50: return "10-50ms"
        case 50..<100: return "50-100ms"
        case 100..<200: return "100-200ms"
        case 200..<500: return "200-500ms"
        case 500..<1000: return "500-1000ms"
        default: return "1000ms+"
        }
    }

    /// Map recording duration (seconds) to a privacy-safe bucket.
    static func durationBucket(seconds: Double) -> String {
        switch seconds {
        case ..<5: return "0-5s"
        case 5..<15: return "5-15s"
        case 15..<30: return "15-30s"
        case 30..<60: return "30-60s"
        default: return "60s+"
        }
    }

    /// Map text length (character count) to a privacy-safe bucket.
    static func lengthBucket(count: Int) -> String {
        switch count {
        case 0: return "0"
        case 1...10: return "1-10"
        case 11...50: return "11-50"
        case 51...200: return "51-200"
        default: return "200+"
        }
    }
}
