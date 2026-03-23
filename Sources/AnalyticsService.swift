import Foundation
import os
import TelemetryDeck

private let analyticsLogger = Logger(subsystem: "com.typeless.app", category: "Analytics")

/// Lightweight wrapper around TelemetryDeck for privacy-first analytics.
///
/// Design principles:
/// - Latency values use precise milliseconds for maximum diagnostic value
/// - Text content is NEVER sent; text lengths are bucketed (e.g. "11-50" not "37")
/// - Users can opt out via Settings toggle (UserDefaults "analyticsEnabled", default true)
/// - DEBUG builds are automatically tagged as test signals by TelemetryDeck
enum AnalyticsService {

    private static let appID = "6EB06114-0222-4BE1-9DDC-BB283B640436"

    /// Initialize TelemetryDeck. Call once from AppDelegate.applicationDidFinishLaunching.
    ///
    /// Always initializes the SDK regardless of enabled state, so that toggling
    /// analytics on later doesn't require re-initialization. The `track()` method
    /// checks `isEnabled` before sending any signals.
    static func initialize() {
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)

        if isEnabled {
            analyticsLogger.info("Analytics initialized (TelemetryDeck)")
        } else {
            analyticsLogger.info("Analytics initialized but disabled by user preference")
        }
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

    /// Update enabled state. TelemetryDeck is already initialized;
    /// this only controls whether `track()` sends signals.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "analyticsEnabled")
        analyticsLogger.info("Analytics \(enabled ? "enabled" : "disabled")")
    }

    /// Track an analytics event with optional parameters.
    static func track(_ event: String, parameters: [String: String] = [:]) {
        guard isEnabled else { return }

        // Attach default parameters
        var params = parameters
        params["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        params["selectedEngine"] = UserDefaults.standard.string(forKey: "selectedASRModel") ?? "streamingParaformer"
        params["cloudRewriteEnabled"] = "\(hasCloudRewriteAPIKey)"

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

    // MARK: - Private Helpers

    /// Whether a Cloud Rewrite API key is configured (user-provided or built-in).
    private static var hasCloudRewriteAPIKey: Bool {
        let userKey = UserDefaults.standard.string(forKey: "cloudRewriteAPIKey") ?? ""
        return !userKey.isEmpty || GeneratedSecrets.cloudRewriteAPIKey != nil
    }
}
