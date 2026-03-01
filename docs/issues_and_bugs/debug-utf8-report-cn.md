# UTF-8 字符乱码（Mojibake）— 根因分析

## Bug 概述

在使用 Qwen3-ASR 进行 E2E 测试时，中文字符（如"地"）在转写输出中显示为 `��`（U+FFFD 替换字符）。

## 根因

**文件：** `crates/qwen-asr/src/tokenizer.rs`，函数 `decode_gpt2_token()`（第 52-65 行）

```rust
// 修复前（有 Bug）
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
    String::from_utf8_lossy(&bytes).into_owned()  // ← BUG：破坏了不完整的 UTF-8 序列
}
```

### 机制

GPT-2 使用**字节级 BPE**，其中每个词表 token 表示一段原始字节序列，通过一个可逆映射编码为 Unicode 码点。BPE 合并操作基于单个字节级符号进行，不考虑 UTF-8 字符边界。

对于多字节 UTF-8 字符（CJK = 3 字节，emoji = 4 字节），一个 BPE token 可能只覆盖**部分**字节：

```
字符："地"
UTF-8 字节：[0xE5, 0x9C, 0xB0]

BPE 可能拆分为：
  Token A → 字节 [0xE5, 0x9C]   （3 字节中的前 2 个）
  Token B → 字节 [0xB0]          （最后 1 个字节）
```

当 `decode_gpt2_token()` 独立处理 Token A 时：
1. 解码为字节 `[0xE5, 0x9C]` — 一个不完整的 3 字节 UTF-8 序列
2. `String::from_utf8_lossy()` 将无效序列替换为 U+FFFD（`�`）
3. **原始字节被永久丢失**

在 `transcribe.rs` 中，token 通过 `tokenizer.decode(token_id)` 逐个解码，返回的是已经被破坏的 `&str`。拼接被破坏的片段永远无法还原原始字符：

```
Token A 解码 → "�"  （原本是 [E5, 9C]）
Token B 解码 → "�"  （原本是 [B0]）
拼接结果     → "��" （而不是"地"）
```

## 修复方案

### 策略：字节级累积，延迟 UTF-8 转换

不再对每个 token 独立进行 UTF-8 转换（这会破坏不完整的序列），改为：

1. **按 token 存储原始字节** — 在 `QwenTokenizer` 中新增 `id_to_bytes: Vec<Option<Vec<u8>>>` 字段
2. **解码时累积字节** — 使用 `text_bytes: Vec<u8>` 替代 `text: String`
3. **仅在最后转换为 UTF-8** — 当完整的字节序列可用时再转换

### 修改的文件

#### `crates/qwen-asr/src/tokenizer.rs`

- 将 `decode_gpt2_token` 重命名为 `decode_gpt2_token_bytes`，返回 `Vec<u8>` 而非 `String`
- 在 `QwenTokenizer` 中新增 `id_to_bytes: Vec<Option<Vec<u8>>>` 字段
- 新增 `decode_bytes(&self, token_id: i32) -> &[u8]` 方法
- 保留 `decode()` → `&str` 以保持向后兼容（使用有损转换）

#### `crates/qwen-asr/src/transcribe.rs`

- `transcribe_segment()`：将 `text: String` 改为 `text_bytes: Vec<u8>`，使用 `decode_bytes()`，在返回时转换为 UTF-8
- `transcribe_stream()`：将 `result: String` 改为 `result_bytes: Vec<u8>`，使用 `decode_bytes()`
- `StreamState`：将 `result: String` 改为 `result_bytes: Vec<u8>`，`text()` 返回 `String`（新分配）
- `stream_push_audio()`：将 `delta: String` 改为 `delta_bytes: Vec<u8>`，使用 `decode_bytes()`
- 所有 `token_cb` 回调仍然接收有损 UTF-8，用于 UI 显示

#### `Frameworks/qwen-asr/lib/libqwen_asr.dylib`

- 从修改后的 Rust 源码重新构建

### 为什么这样能修复

修复后，连续 token 的字节会在字节级别进行拼接：

```
Token A 字节：[0xE5, 0x9C]
Token B 字节：[0xB0]
累积结果：    [0xE5, 0x9C, 0xB0]  ← "地"的有效 UTF-8 编码

String::from_utf8_lossy([0xE5, 0x9C, 0xB0]) → "地"  ✓
```

## 受影响的字符

任何需要多字节 UTF-8 编码且 BPE 在字节边界处拆分的字符：
- **CJK 字符**（3 字节）：中文、日文汉字、韩文汉字
- **扩展拉丁字符**（2 字节）：带重音的字符（é、ñ、ü 等）
- **Emoji**（4 字节）：所有 emoji 字符
- **其他文字**：西里尔字母、阿拉伯语、泰语等

## 验证方法

```bash
# 重新构建 Rust 库
cd scripts/.qwen-asr-build/QwenASR
cargo build --release

# 复制到 Frameworks
cp target/release/libqwen_asr.dylib ../../Frameworks/qwen-asr/lib/
install_name_tool -id @rpath/libqwen_asr.dylib ../../Frameworks/qwen-asr/lib/libqwen_asr.dylib
codesign --force --sign - ../../Frameworks/qwen-asr/lib/libqwen_asr.dylib

# 构建并测试
xcodebuild -scheme Typeless -configuration Debug build
```

Rust `cargo build` 和 Xcode `xcodebuild` 均构建通过。

## 回归测试套件

### Rust 单元测试（`crates/qwen-asr/src/tokenizer.rs`）

`#[cfg(test)] mod tests` 中共 9 个测试：

| 测试 | 验证内容 |
|------|---------|
| `test_roundtrip_ascii` | ASCII 字节在编码 → 解码往返中保持不变 |
| `test_roundtrip_cjk_full_char` | "地"（3 字节）在单个 token 中正确往返 |
| `test_decode_bytes_split_utf8_cjk` | [E5,9C] + [B0]（拆分的"地"）拼接后为有效 UTF-8 |
| `test_decode_bytes_split_utf8_2byte_char` | [C3] + [A9]（拆分的"é"）拼接后为有效 UTF-8 |
| `test_decode_bytes_split_utf8_4byte_emoji` | [F0,9F] + [A6,80]（拆分的"🦀"）拼接后为有效 UTF-8 |
| `test_decode_bytes_mixed_content_rust_crab_chinese` | "Rust🦀真棒" 逐字节 token 的最坏情况 |
| `test_lossy_corruption_proof` | 证明旧的有损路径确实会破坏数据，新的字节路径不会 |
| `test_gpt2_mapping_all_256_bytes_roundtrip` | 所有 256 个字节在 GPT-2 映射往返中保持不变 |
| `test_gpt2_mapping_is_bijective` | GPT-2 字节↔Unicode 映射是一一对应的 |

```bash
cd scripts/.qwen-asr-build/QwenASR && cargo test -p qwen-asr
# test result: ok. 9 passed; 0 failed
```

### Swift E2E 压力测试（`TypelessTests/QwenASRE2ETests.swift`）

`QwenASRE2ETests` 中新增 4 个测试方法：

| 测试 | Chunk 大小 | 音频来源 | 关键断言 |
|------|-----------|---------|---------|
| `testStreamingWithTinyChunks_AvoidsMojibake` | 320（20ms） | edge_tts zh_short_01 | 结果和所有 delta 中不含 U+FFFD |
| `testStreamingSmallChunks_MultipleAudio_NoMojibake` | 1024（64ms） | zh_short、mixed_01/02 | 多个中文音频文件中不含 U+FFFD |
| `testStreamingRealAudio_TinyChunks_NoMojibake` | 640（40ms） | AISHELL 真实录音 | 真实中文语音中不含 U+FFFD |
| `testStreamingDeltaConsistency_NoMojibake` | 640（40ms） | edge_tts zh_short_01 | 不含 U+FFFD 且 delta 累积结果与 getResult 一致 |
