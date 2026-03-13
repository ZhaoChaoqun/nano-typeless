import Foundation

/// Benchmark 用的条目：包含已解析的音频绝对路径
struct BenchmarkEntry {
    let id: String
    let category: String
    let expectedTexts: [String]
    let audioPath: String
    let durationSec: Double
    let language: String
    let source: String  // "synthetic" or "recorded"
}

/// 从 synthetic_manifest.json 和 recorded_manifest.json 加载并合并所有可用的 benchmark 条目
enum BenchmarkEntryLoader {

    static func loadAll(fixturesPath: String) -> [BenchmarkEntry] {
        var entries: [BenchmarkEntry] = []

        // synthetic_manifest.json
        let corpusPath = fixturesPath + "/synthetic_manifest.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: corpusPath)),
           let corpus = try? JSONDecoder().decode(Corpus.self, from: data) {
            for e in corpus.entries {
                if let audioPath = resolveAudioPath(e, fixturesPath: fixturesPath, preference: ["synthetic"]) {
                    entries.append(BenchmarkEntry(
                        id: e.id, category: e.category, expectedTexts: e.expectedTexts,
                        audioPath: audioPath, durationSec: e.durationSec,
                        language: e.language, source: "synthetic"
                    ))
                }
            }
        }

        // recorded_manifest.json
        let realPath = fixturesPath + "/recorded_manifest.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: realPath)),
           let manifest = try? JSONDecoder().decode(Corpus.self, from: data) {
            for e in manifest.entries {
                if let audioPath = resolveAudioPath(e, fixturesPath: fixturesPath, preference: ["recorded"]) {
                    entries.append(BenchmarkEntry(
                        id: e.id, category: e.category, expectedTexts: e.expectedTexts,
                        audioPath: audioPath, durationSec: e.durationSec,
                        language: e.language, source: "recorded"
                    ))
                }
            }
        }

        return entries
    }

    private static func resolveAudioPath(_ entry: CorpusEntry, fixturesPath: String, preference: [String]) -> String? {
        for source in preference {
            if let relPath = entry.audioFiles[source] {
                let fullPath = fixturesPath + "/" + relPath
                if FileManager.default.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        return nil
    }
}
