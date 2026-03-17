import Foundation

// MARK: - Codable 数据模型

struct TestResultEntry: Codable {
    let id: String
    let category: String
    let language: String
    let expectedText: String
    let actualText: String
    let cer: Double
    let passed: Bool
    let matchMode: String
    let elapsedSec: Double
    let audioDurationSec: Double
    let rtf: Double
    let memoryBeforeMB: Double?
    let memoryAfterMB: Double?

    enum CodingKeys: String, CodingKey {
        case id, category, language, cer, passed, rtf
        case expectedText = "expected_text"
        case actualText = "actual_text"
        case matchMode = "match_mode"
        case elapsedSec = "elapsed_sec"
        case audioDurationSec = "audio_duration_sec"
        case memoryBeforeMB = "memory_before_mb"
        case memoryAfterMB = "memory_after_mb"
    }
}

struct TestResultSummary: Codable {
    let totalEntries: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let avgCer: Double
    let medianCer: Double
    let totalAudioDurationSec: Double
    let totalInferenceTimeSec: Double
    let rtf: Double

    enum CodingKeys: String, CodingKey {
        case passed, failed, skipped, rtf
        case totalEntries = "total_entries"
        case avgCer = "avg_cer"
        case medianCer = "median_cer"
        case totalAudioDurationSec = "total_audio_duration_sec"
        case totalInferenceTimeSec = "total_inference_time_sec"
    }
}

struct PipelineResults: Codable {
    let pipelineName: String
    let summary: TestResultSummary
    let entries: [TestResultEntry]

    enum CodingKeys: String, CodingKey {
        case entries, summary
        case pipelineName = "pipeline_name"
    }
}

struct TestResultReport: Codable {
    let schemaVersion: Int
    let suite: String
    let timestamp: String
    let gitCommit: String
    let gitBranch: String
    let pipelines: [PipelineResults]

    enum CodingKeys: String, CodingKey {
        case suite, timestamp, pipelines
        case schemaVersion = "schema_version"
        case gitCommit = "git_commit"
        case gitBranch = "git_branch"
    }
}

// MARK: - 结果收集器

/// 在测试运行期间收集结果，最后一次性写出 JSON
class TestResultCollector {

    static let shared = TestResultCollector()

    private var pipelineEntries: [String: [TestResultEntry]] = [:]
    private let lock = NSLock()

    func record(pipelineName: String, entry: TestResultEntry) {
        lock.lock()
        defer { lock.unlock() }
        pipelineEntries[pipelineName, default: []].append(entry)
    }

    func writeJSON(suite: String) {
        lock.lock()
        let snapshot = pipelineEntries
        lock.unlock()

        // 读取 run_tests.sh 写入的配置文件（xcodebuild 不传递 shell 环境变量给测试进程）
        let config = Self.loadRunConfig()
        let outputPath = config["json_path"] ?? NSTemporaryDirectory() + "typeless_\(suite)_results.json"
        let gitCommit = config["git_commit"] ?? "unknown"
        let gitBranch = config["git_branch"] ?? "unknown"

        let pipelines = snapshot.keys.sorted().compactMap { name -> PipelineResults? in
            guard let entries = snapshot[name] else { return nil }
            return PipelineResults(
                pipelineName: name,
                summary: computeSummary(entries: entries),
                entries: entries
            )
        }

        let report = TestResultReport(
            schemaVersion: 1,
            suite: suite,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            gitCommit: gitCommit,
            gitBranch: gitBranch,
            pipelines: pipelines
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(report)
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("[TestResultCollector] JSON written to: \(outputPath)")
        } catch {
            print("[TestResultCollector] Failed to write JSON: \(error)")
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        pipelineEntries.removeAll()
    }

    // MARK: - Private

    private func computeSummary(entries: [TestResultEntry]) -> TestResultSummary {
        let passedCount = entries.filter(\.passed).count
        let failedCount = entries.count - passedCount
        let cers = entries.map(\.cer).sorted()
        let avgCer = cers.isEmpty ? 0.0 : cers.reduce(0, +) / Double(cers.count)
        let medianCer: Double = {
            guard !cers.isEmpty else { return 0.0 }
            let mid = cers.count / 2
            return cers.count % 2 == 0 ? (cers[mid - 1] + cers[mid]) / 2.0 : cers[mid]
        }()
        let totalAudio = entries.map(\.audioDurationSec).reduce(0, +)
        let totalInference = entries.map(\.elapsedSec).reduce(0, +)
        let rtf = totalAudio > 0 ? totalInference / totalAudio : 0

        return TestResultSummary(
            totalEntries: entries.count,
            passed: passedCount,
            failed: failedCount,
            skipped: 0,
            avgCer: avgCer,
            medianCer: medianCer,
            totalAudioDurationSec: totalAudio,
            totalInferenceTimeSec: totalInference,
            rtf: rtf
        )
    }

    /// 从临时配置文件读取 run_tests.sh 传入的参数
    /// 文件格式：每行 "key=value"，位于 /tmp/typeless_test_config.txt
    private static func loadRunConfig() -> [String: String] {
        let configPath = "/tmp/typeless_test_config.txt"
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return [:]
        }
        var config: [String: String] = [:]
        for line in content.split(separator: "\n") {
            if let eqIdx = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<eqIdx])
                let value = String(line[line.index(after: eqIdx)...])
                config[key] = value
            }
        }
        return config
    }
}
