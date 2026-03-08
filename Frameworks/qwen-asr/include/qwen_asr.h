#ifndef QWEN_ASR_H
#define QWEN_ASR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to the QwenASR engine
typedef struct QwenAsrEngine QwenAsrEngine;

/// Load a Qwen3-ASR model from disk.
/// @param model_dir Path to the model directory containing safetensors, vocab.json, etc.
/// @param n_threads Number of inference threads (<=0 for auto-detect)
/// @param verbosity Log verbosity level (0 = quiet)
/// @return Engine handle, or NULL on failure
QwenAsrEngine* qwen_asr_load_model(const char* model_dir, int32_t n_threads, int32_t verbosity);

/// Free the engine and all associated resources.
void qwen_asr_free(QwenAsrEngine* engine);

/// Check if the engine is using INT8 quantized decoder.
/// @return 1 if INT8, 0 if BF16, -1 if engine is null
int32_t qwen_asr_is_int8(const QwenAsrEngine* engine);

/// Transcribe raw PCM audio.
/// @param engine Engine handle
/// @param samples Pointer to float32 PCM samples (16kHz, mono, range [-1,1])
/// @param n_samples Number of samples
/// @return Heap-allocated UTF-8 string. Caller must free with qwen_asr_free_string().
char* qwen_asr_transcribe_pcm(QwenAsrEngine* engine, const float* samples, int32_t n_samples);

/// Transcribe a WAV file from disk.
/// @param engine Engine handle
/// @param wav_path Path to a WAV file
/// @return Heap-allocated UTF-8 string. Caller must free with qwen_asr_free_string().
char* qwen_asr_transcribe_file(QwenAsrEngine* engine, const char* wav_path);

/// Transcribe a WAV buffer in memory.
/// @param engine Engine handle
/// @param wav_data Pointer to raw WAV data (including header)
/// @param wav_len Length of wav_data in bytes
/// @return Heap-allocated UTF-8 string. Caller must free with qwen_asr_free_string().
char* qwen_asr_transcribe_wav_buffer(QwenAsrEngine* engine, const uint8_t* wav_data, int32_t wav_len);

/// Set the segmentation duration for long audio.
/// @param sec Segment duration in seconds (0 = no segmentation)
void qwen_asr_set_segment_sec(QwenAsrEngine* engine, float sec);

/// Force a specific language for transcription.
/// @param language Language name (e.g. "chinese", "english"), or empty string for auto-detect
/// @return 0 on success, -1 on failure (unknown language)
int32_t qwen_asr_set_language(QwenAsrEngine* engine, const char* language);

/// Free a string returned by qwen_asr_transcribe_* or qwen_asr_stream_*.
void qwen_asr_free_string(char* s);

/// Enable or disable GPU acceleration at runtime.
/// @param use_gpu 1 = GPU (Metal), 0 = CPU-only
void qwen_asr_set_use_gpu(QwenAsrEngine* engine, int32_t use_gpu);

// ========================================================================
// Streaming API
// ========================================================================

/// Opaque handle to streaming state
typedef struct QwenAsrStreamState QwenAsrStreamState;

/// Create a new streaming state.
/// @return Stream state handle, or NULL on failure
QwenAsrStreamState* qwen_asr_stream_new(void);

/// Free a streaming state and all associated resources.
void qwen_asr_stream_free(QwenAsrStreamState* stream);

/// Reset streaming state for a new utterance (reuses allocations).
void qwen_asr_stream_reset(QwenAsrStreamState* stream);

/// Push new audio samples and get incremental text delta.
/// @param engine Engine handle
/// @param stream Streaming state handle
/// @param samples Pointer to new float32 PCM samples (16kHz, mono)
/// @param n_samples Number of new samples
/// @param finalize Set to 1 to signal end-of-stream and flush remaining tokens
/// @return Heap-allocated UTF-8 delta string, or NULL if nothing new.
///         Caller must free with qwen_asr_free_string().
char* qwen_asr_stream_push(QwenAsrEngine* engine, QwenAsrStreamState* stream,
                           const float* samples, int32_t n_samples, int32_t finalize);

/// Get the full accumulated transcription result so far.
/// @return Heap-allocated UTF-8 string, or NULL if empty.
///         Caller must free with qwen_asr_free_string().
char* qwen_asr_stream_get_result(QwenAsrStreamState* stream);

/// Configure streaming chunk size in seconds (default 2.0).
void qwen_asr_stream_set_chunk_sec(QwenAsrEngine* engine, float sec);

/// Configure token rollback window (default 5).
void qwen_asr_stream_set_rollback(QwenAsrEngine* engine, int32_t tokens);

/// Configure unfixed chunks count before emitting (default 2).
void qwen_asr_stream_set_unfixed_chunks(QwenAsrEngine* engine, int32_t chunks);

/// Configure max new tokens per chunk (default 32).
void qwen_asr_stream_set_max_new_tokens(QwenAsrEngine* engine, int32_t tokens);

/// Get currently decoded but not-yet-stable (speculative) text.
/// @return Heap-allocated UTF-8 string, or NULL if empty.
///         Caller must free with qwen_asr_free_string().
char* qwen_asr_stream_get_unfixed(QwenAsrStreamState* stream);

#ifdef __cplusplus
}
#endif

#endif // QWEN_ASR_H
