# UTF-8 Character Corruption (Mojibake) — Root Cause Analysis

## Bug Summary

During E2E testing with Qwen3-ASR, Chinese characters (e.g. "地") appear as `��` (U+FFFD Replacement Character) in the transcription output.

## Root Cause

**File:** `crates/qwen-asr/src/tokenizer.rs`, function `decode_gpt2_token()` (line 52-65)

```rust
// BEFORE (buggy)
fn decode_gpt2_token(token_str: &str, unicode_to_byte: &[i32; 512]) -> String {
    let mut bytes = Vec::new();
    for ch in token_str.chars() {
        let cp = ch as u32;
        if cp < 512 && unicode_to_byte[cp as usize] >= 0 {
            bytes.push(unicode_to_byte[cp as usize] as u8);
        } else {
            bytes.push(b'?');
        }
    }
    String::from_utf8_lossy(&bytes).into_owned()  // ← BUG: corrupts partial UTF-8
}
```

### Mechanism

GPT-2 uses **byte-level BPE** where each vocabulary token represents a sequence of raw bytes, encoded as Unicode codepoints via a reversible mapping. BPE merging operates on individual byte-level symbols without respect for UTF-8 character boundaries.

For multi-byte UTF-8 characters (CJK = 3 bytes, emoji = 4 bytes), a single BPE token may cover only **part** of the bytes:

```
Character: "地"
UTF-8 bytes: [0xE5, 0x9C, 0xB0]

BPE might split as:
  Token A → bytes [0xE5, 0x9C]   (first 2 of 3 bytes)
  Token B → bytes [0xB0]          (last byte)
```

When `decode_gpt2_token()` processes Token A independently:
1. Decodes to bytes `[0xE5, 0x9C]` — an incomplete 3-byte UTF-8 sequence
2. `String::from_utf8_lossy()` replaces the invalid sequence with U+FFFD (`�`)
3. **The original bytes are permanently lost**

In `transcribe.rs`, tokens are decoded individually via `tokenizer.decode(token_id)`, which returns the pre-corrupted `&str`. Concatenating corrupted pieces never reconstructs the original character:

```
Token A decode → "�"  (was [E5, 9C])
Token B decode → "�"  (was [B0])
Concatenated   → "��" (instead of "地")
```

## Fix Applied

### Strategy: Byte-level accumulation, deferred UTF-8 conversion

Instead of converting each token to UTF-8 independently (which corrupts partial sequences), we:

1. **Store raw bytes per token** — new `id_to_bytes: Vec<Option<Vec<u8>>>` in `QwenTokenizer`
2. **Accumulate bytes during decoding** — `text_bytes: Vec<u8>` instead of `text: String`
3. **Convert to UTF-8 only at the end** — when the full byte sequence is available

### Files Modified

#### `crates/qwen-asr/src/tokenizer.rs`

- Renamed `decode_gpt2_token` → `decode_gpt2_token_bytes`, returns `Vec<u8>` instead of `String`
- Added `id_to_bytes: Vec<Option<Vec<u8>>>` field to `QwenTokenizer`
- Added `decode_bytes(&self, token_id: i32) -> &[u8]` method
- Kept `decode()` → `&str` for backward compatibility (uses lossy conversion)

#### `crates/qwen-asr/src/transcribe.rs`

- `transcribe_segment()`: changed `text: String` → `text_bytes: Vec<u8>`, uses `decode_bytes()`, converts to UTF-8 at return
- `transcribe_stream()`: changed `result: String` → `result_bytes: Vec<u8>`, uses `decode_bytes()`
- `StreamState`: changed `result: String` → `result_bytes: Vec<u8>`, `text()` returns `String` (allocated)
- `stream_push_audio()`: changed `delta: String` → `delta_bytes: Vec<u8>`, uses `decode_bytes()`
- All `token_cb` callbacks still receive lossy UTF-8 for UI display purposes

#### `Frameworks/qwen-asr/lib/libqwen_asr.dylib`

- Rebuilt from modified Rust source

### Why This Works

After the fix, bytes from consecutive tokens are concatenated at the byte level:

```
Token A bytes: [0xE5, 0x9C]
Token B bytes: [0xB0]
Accumulated:   [0xE5, 0x9C, 0xB0]  ← valid UTF-8 for "地"

String::from_utf8_lossy([0xE5, 0x9C, 0xB0]) → "地"  ✓
```

## Affected Characters

Any character requiring multi-byte UTF-8 encoding where BPE splits across byte boundaries:
- **CJK characters** (3 bytes): Chinese, Japanese Kanji, Korean Hanja
- **Extended Latin** (2 bytes): accented characters (é, ñ, ü, etc.)
- **Emoji** (4 bytes): all emoji characters
- **Other scripts**: Cyrillic, Arabic, Thai, etc.

## Verification

```bash
# Rebuild Rust library
cd scripts/.qwen-asr-build/QwenASR
cargo build --release

# Copy to Frameworks
cp target/release/libqwen_asr.dylib ../../Frameworks/qwen-asr/lib/
install_name_tool -id @rpath/libqwen_asr.dylib ../../Frameworks/qwen-asr/lib/libqwen_asr.dylib
codesign --force --sign - ../../Frameworks/qwen-asr/lib/libqwen_asr.dylib

# Build and test
xcodebuild -scheme Typeless -configuration Debug build
```

Both Rust `cargo build` and Xcode `xcodebuild` pass successfully.

## Regression Test Suite

### Rust Unit Tests (`crates/qwen-asr/src/tokenizer.rs`)

9 tests in `#[cfg(test)] mod tests`:

| Test | What It Verifies |
|------|-----------------|
| `test_roundtrip_ascii` | ASCII bytes survive encode → decode round-trip |
| `test_roundtrip_cjk_full_char` | "地" (3 bytes) round-trips correctly when in one token |
| `test_decode_bytes_split_utf8_cjk` | [E5,9C] + [B0] (split "地") concatenates to valid UTF-8 |
| `test_decode_bytes_split_utf8_2byte_char` | [C3] + [A9] (split "é") concatenates to valid UTF-8 |
| `test_decode_bytes_split_utf8_4byte_emoji` | [F0,9F] + [A6,80] (split "🦀") concatenates to valid UTF-8 |
| `test_decode_bytes_mixed_content_rust_crab_chinese` | "Rust🦀真棒" byte-per-token worst-case |
| `test_lossy_corruption_proof` | Proves old lossy path DOES corrupt, new byte path DOES NOT |
| `test_gpt2_mapping_all_256_bytes_roundtrip` | All 256 bytes survive GPT-2 mapping round-trip |
| `test_gpt2_mapping_is_bijective` | GPT-2 byte↔unicode mapping is 1:1 |

```bash
cd scripts/.qwen-asr-build/QwenASR && cargo test -p qwen-asr
# test result: ok. 9 passed; 0 failed
```

### Swift E2E Stress Tests (`TypelessTests/QwenASRE2ETests.swift`)

4 new test methods in `QwenASRE2ETests`:

| Test | Chunk Size | Audio Source | Key Assertion |
|------|-----------|-------------|---------------|
| `testStreamingWithTinyChunks_AvoidsMojibake` | 320 (20ms) | edge_tts zh_short_01 | No U+FFFD in result or any delta |
| `testStreamingSmallChunks_MultipleAudio_NoMojibake` | 1024 (64ms) | zh_short, mixed_01/02 | No U+FFFD across multiple Chinese audio files |
| `testStreamingRealAudio_TinyChunks_NoMojibake` | 640 (40ms) | AISHELL real recordings | No U+FFFD in real-world Chinese speech |
| `testStreamingDeltaConsistency_NoMojibake` | 640 (40ms) | edge_tts zh_short_01 | No U+FFFD + delta accumulation matches getResult |

