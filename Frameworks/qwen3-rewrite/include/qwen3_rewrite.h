#ifndef QWEN3_REWRITE_H
#define QWEN3_REWRITE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RewriteEngine RewriteEngine;

/// Load rewrite model from a directory path. Returns NULL on failure.
/// n_threads: 0 = auto-detect. verbosity: 0=quiet, 1=info, 2=debug.
RewriteEngine* qwen3_rewrite_load(const char* model_dir, int32_t n_threads, int32_t verbosity);

/// Rewrite input text. Returns heap-allocated C string, or NULL on failure.
/// Caller must free with qwen3_rewrite_free_string().
char* qwen3_rewrite_text(RewriteEngine* engine, const char* input_text);

/// Enable or disable GPU acceleration (1 = GPU, 0 = CPU-only).
void qwen3_rewrite_set_use_gpu(RewriteEngine* engine, int32_t use_gpu);

/// Free a string returned by qwen3_rewrite_text().
void qwen3_rewrite_free_string(char* s);

/// Free the engine.
void qwen3_rewrite_free(RewriteEngine* engine);

#ifdef __cplusplus
}
#endif

#endif /* QWEN3_REWRITE_H */
