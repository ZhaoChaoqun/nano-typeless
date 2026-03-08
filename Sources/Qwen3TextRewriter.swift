import Foundation

/// Swift wrapper for the Qwen3-0.6B text rewrite engine (C FFI).
/// Provides ASR post-processing: ITN + punctuation + CSC + terminology normalization.
class Qwen3TextRewriter {
    private var engine: OpaquePointer?

    /// Initialize with path to model directory containing model_int8.qint8 + tokenizer.json.
    init?(modelDir: String) {
        engine = qwen3_rewrite_load(modelDir, 0, 1)
        guard engine != nil else {
            print("[Qwen3TextRewriter] Failed to load model from \(modelDir)")
            return nil
        }
        print("[Qwen3TextRewriter] Model loaded from \(modelDir)")
    }

    deinit {
        if let engine = engine {
            qwen3_rewrite_free(engine)
        }
    }

    /// Rewrite ASR text: add punctuation, correct errors, normalize numbers.
    /// Returns original text if rewrite fails.
    func rewrite(text: String) -> String {
        guard let engine = engine else { return text }
        guard !text.isEmpty else { return text }

        guard let result = qwen3_rewrite_text(engine, text) else {
            return text
        }
        defer { qwen3_rewrite_free_string(result) }
        return String(cString: result)
    }

    /// Enable or disable GPU acceleration.
    func setUseGPU(_ useGPU: Bool) {
        guard let engine = engine else { return }
        qwen3_rewrite_set_use_gpu(engine, useGPU ? 1 : 0)
    }
}
