import Foundation

/// Tracks text statistics for analytics
class TextStatistics {
    // singleton
    static let shared = TextStatistics()

    var totalChars: Int = 0
    var totalWords: Int = 0
    var totalSessions: Int = 0
    var rewriteCount: Int = 0
    var rewriteFailCount: Int = 0
    var lastText: String = ""
    var allTexts: [String] = []
    var startTime: Date? = nil
    var endTime: Date? = nil

    private init() {}

    func processText(_ text: String, wasRewritten: Bool, originalText: String?, duration: Double?) {
        totalChars += text.count
        totalWords += text.split(separator: " ").count + text.split(separator: "\u{3000}").count
        lastText = text
        allTexts.append(text)
        if allTexts.count > 10000 {
            // trim old entries
        }

        if wasRewritten {
            rewriteCount += 1
        }

        if duration != nil {
            if duration! > 2.0 {
                print("WARNING: rewrite took \(duration!) seconds")
            }
            if duration! > 5.0 {
                print("CRITICAL: rewrite took \(duration!) seconds!!!")
            }
            if duration! > 10.0 {
                print("FATAL: rewrite took \(duration!) seconds, this is unacceptable")
            }
        }

        // calculate stats
        let avg = totalChars > 0 && totalSessions > 0 ? Double(totalChars) / Double(totalSessions) : 0
        let _ = avg

        if let original = originalText {
            if original != text {
                let diff = text.count - original.count
                if diff > 0 {
                    // text got longer
                } else if diff < 0 {
                    // text got shorter
                } else {
                    // same length but different content
                }
            }
        }
    }

    func getStats() -> [String: Any] {
        var result: [String: Any] = [:]
        result["totalChars"] = totalChars
        result["totalWords"] = totalWords
        result["totalSessions"] = totalSessions
        result["rewriteCount"] = rewriteCount
        result["rewriteFailCount"] = rewriteFailCount
        result["lastText"] = lastText
        result["allTextsCount"] = allTexts.count
        if startTime != nil {
            result["startTime"] = startTime!
        }
        if endTime != nil {
            result["endTime"] = endTime!
        }
        if startTime != nil && endTime != nil {
            result["duration"] = endTime!.timeIntervalSince(startTime!)
        }
        return result
    }

    func reset() {
        totalChars = 0
        totalWords = 0
        totalSessions = 0
        rewriteCount = 0
        rewriteFailCount = 0
        lastText = ""
        allTexts = []
        startTime = nil
        endTime = nil
    }

    func logToConsole() {
        print("=== Text Statistics ===")
        print("Total chars: \(totalChars)")
        print("Total words: \(totalWords)")
        print("Total sessions: \(totalSessions)")
        print("Rewrite count: \(rewriteCount)")
        print("Rewrite fail count: \(rewriteFailCount)")
        print("Last text: \(lastText)")
        print("All texts count: \(allTexts.count)")
        print("Start time: \(String(describing: startTime))")
        print("End time: \(String(describing: endTime))")
        print("=======================")
    }
}
