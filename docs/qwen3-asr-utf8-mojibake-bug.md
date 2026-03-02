# Qwen3-ASR UTF-8 乱码 (Mojibake) Bug 分析与修复

## 现象

Benchmark 测试中，Qwen3-ASR 在离线和流式模式均出现乱码输出，涉及两种不同的乱码模式：

### 模式 1：U+FFFD 替换字符 (�)

| 条目 | 模式 | 期望文本 | 实际输出 |
|------|------|---------|---------|
| `dev_url_01` | 离线+流式 | `访问github.com。` | `访问 GitHub ��� com。` |
| `cs_edge_003` | 离线+流式 | `用Docker Compose部署了3个microservice到staging环境。` | `用 Docker Compose ���署了三个 microservice �� staging ���境。` |

`部` → `���署`，`到` → `��`，`环` → `���` — 多字节中文字符被替换为 U+FFFD。

### 模式 2：繁体字 + Box Drawing 字符 (──)

| 条目 | 模式 | 期望文本 | 实际输出 |
|------|------|---------|---------|
| `conv_zh_004` | 流式 | `我想要查询我的账户余额。` | `我想要查詢我的──戶餘額。` |

`账` → `──戶`，`余` → `餘` — 简体字变为繁体，且出现 Box Drawing 字符。

---

## 根因分析

### 背景：GPT-2 Byte-level BPE Tokenizer

Qwen3-ASR 使用 GPT-2 风格的 Byte-level BPE Tokenizer。其核心特性：

1. **每个 token 映射到原始字节**，而非 Unicode 字符串
2. **一个多字节 UTF-8 字符（如中文 3 字节）可以被拆分到多个 BPE token 中**

例如 `地址` 的 UTF-8 编码是 `[0xE5, 0x9C, 0xB0, 0xE5, 0x9D, 0x80]`，BPE 可能将其分割为：
- Token A → `[0xE5, 0x9C]`（`地` 的前 2 字节）
- Token B → `[0xB0, 0xE5]`（`地` 的第 3 字节 + `址` 的第 1 字节）
- Token C → `[0x9D, 0x80]`（`址` 的后 2 字节）

### 核心问题：流式解码中 rollback 边界切断多字节字符

`stream_push_audio()` 内部按 chunk（默认 2 秒）处理音频。每个 chunk 解码后，使用 rollback 机制确定稳定边界：

```rust
let candidate_len = (n_text_tokens as i32 - rollback).max(0) as usize;
```

rollback 按 **token 计数** 截断，不感知 UTF-8 字节边界。当 rollback 边界恰好落在"跨字符 token"上时：

```
chunk N 稳定 tokens:  [..., Token_A(0xE5,0x9C)]       ← 不完整的「地」
chunk N+1 新增 tokens: [Token_B(0xB0,0xE5), Token_C(0x9D,0x80), ...]
```

`result_bytes` 在 chunk N 后包含 `[..., 0xE5, 0x9C]`，是不完整的 UTF-8 序列。

### 触发损坏的时机

Swift 端在每次 `processAudio()` 后调用 `getResult()` 获取当前识别文本。`getResult()` 调用 `StreamState::text()`，最终执行：

```rust
// 修复前的实现
pub fn text(&self) -> &str {
    &self.result  // result 是 String，每次 push_str 时已经 lossy 了
}
```

修复前的代码路径是：每个 token 解码时直接调用 `tokenizer.decode(token_id)` 返回 `&str`（内部使用 `from_utf8_lossy`），然后 `push_str` 拼接。这意味着 **每个 token 独立做 lossy 转换**：

```
Token_A 的 bytes [0xE5, 0x9C] → from_utf8_lossy → "�" (U+FFFD)
Token_B 的 bytes [0xB0, 0xE5] → from_utf8_lossy → "�" (U+FFFD)
```

正确结果应该是将所有字节拼接后再转换：`[0xE5, 0x9C, 0xB0, 0xE5, ...]` → `"地..."`.

### 模式 2 乱码的来源

Box Drawing 字符 `──`（U+2500）和繁体字可能来自以下原因组合：
- `decode_gpt2_token_bytes()` 对 Unicode 码点 ≥ 512 的字符使用 `b'?'` (0x3F) 作为 fallback
- 0x3F 恰好可能与相邻 token 的字节组成其他 UTF-8 字符序列
- 这是模型产生了非标准 token 组合的结果，非编码层面能完全避免

---

## 修复方案

### 核心思路：字节累积 + UTF-8 安全边界

放弃逐 token 做 `from_utf8_lossy` 的方式，改为：
1. 逐 token 累积原始字节到 `Vec<u8>`
2. 仅在输出时做一次 `from_utf8_lossy`
3. 输出前检查 UTF-8 安全边界，保留不完整的尾部字节

### 修改文件

`crates/qwen-asr/src/transcribe.rs`

### 修改 1：添加 `utf8_safe_boundary()` 函数

```rust
/// 返回 bytes 中最后一个完整 UTF-8 字符的结束位置。
/// bytes[..safe_end] 保证是有效 UTF-8，
/// bytes[safe_end..] 包含不完整的尾部多字节序列。
fn utf8_safe_boundary(bytes: &[u8]) -> usize {
    let len = bytes.len();
    if len == 0 { return 0; }
    // 向后扫描最多 4 字节，找到最后一个 leading byte
    let mut i = len;
    while i > 0 && i > len.saturating_sub(4) {
        i -= 1;
        let b = bytes[i];
        if b & 0xC0 != 0x80 {
            // 找到 leading byte，检查序列是否完整
            let expected_len = match b {
                0x00..=0x7F => 1,
                0xC0..=0xDF => 2,
                0xE0..=0xEF => 3,
                0xF0..=0xF7 => 4,
                _ => 1,
            };
            return if i + expected_len <= len { len } else { i };
        }
    }
    len
}
```

算法原理：
- 从末尾向前扫描最多 4 字节（UTF-8 最大编码长度）
- 找到 leading byte 后，计算该字符的期望字节数
- 如果实际剩余字节足够 → 返回 `len`（全部完整）
- 如果不够 → 返回 leading byte 位置（截断不完整部分）

### 修改 2：`StreamState` 新增 `pending_delta_bytes` 字段

```rust
pub struct StreamState {
    // ... 其他字段 ...
    result_bytes: Vec<u8>,          // 替代原来的 result: String
    pending_delta_bytes: Vec<u8>,   // 新增：跨调用的不完整 UTF-8 尾部
}
```

### 修改 3：`StreamState::text()` 使用安全边界

```rust
pub fn text(&self) -> String {
    let safe_end = utf8_safe_boundary(&self.result_bytes);
    String::from_utf8_lossy(&self.result_bytes[..safe_end]).into_owned()
}
```

中间状态调用 `text()` 时，不完整的尾部字节被安全排除，等后续 token 补齐后自然变为完整字符。

### 修改 4：`stream_push_audio()` delta 返回安全处理

```rust
// 函数开头：回收上次遗留的不完整字节
let mut delta_bytes: Vec<u8> = std::mem::take(&mut state.pending_delta_bytes);

// ... token 解码循环中 ...
let piece_bytes = tokenizer.decode_bytes(candidate_tokens[i]);
state.result_bytes.extend_from_slice(piece_bytes);
delta_bytes.extend_from_slice(piece_bytes);

// 返回前：分离不完整的尾部
let safe_end = utf8_safe_boundary(&delta_bytes);
if safe_end < delta_bytes.len() {
    state.pending_delta_bytes = delta_bytes[safe_end..].to_vec();
    delta_bytes.truncate(safe_end);
}
Some(String::from_utf8_lossy(&delta_bytes).into_owned())
```

---

## 修复范围

| 代码路径 | 修复内容 |
|----------|---------|
| `transcribe_segment()` (离线) | `text: String` → `text_bytes: Vec<u8>`，最终一次性 `from_utf8_lossy` |
| `transcribe_stream()` (一次性流式) | `result: String` → `result_bytes: Vec<u8>`，最终一次性 `from_utf8_lossy` |
| `StreamState::text()` | 返回 `String`，使用 `utf8_safe_boundary` 截取安全 UTF-8 |
| `stream_push_audio()` delta | `pending_delta_bytes` 机制保证跨调用的 UTF-8 完整性 |
| token callback (`ctx.token_cb`) | 改用 `String::from_utf8_lossy(piece_bytes)` 做 lossy 显示 |

所有修改已整合到 patch 文件：`scripts/qwen-asr-macos-streaming.patch`

---

## 验证结果

### 离线模式

| 条目 | 修复前 CER | 修复前输出 | 修复后 CER | 修复后输出 |
|------|-----------|-----------|-----------|-----------|
| `dev_url_01` | 0.231 | `访问 GitHub ��� com。` | **0.077** | `访问 GitHub 点 com。` |
| `conv_zh_004` | 0.000 | *(离线无乱码)* | **0.000** | *(完全匹配)* |
| `cs_edge_003` | 0.214 | `Docker Compose ���署了三个 microservice ── staging ───境。` | **0.024** | `Docker Compose 部署了三个 microservice 到 staging 环境。` |

### 流式模式

| 条目 | 修复前 CER | 修复前输出 | 修复后 CER | 修复后输出 |
|------|-----------|-----------|-----------|-----------|
| `dev_url_01` | 0.231 | `访问 GitHub ��� com。` | **0.077** | `访问 GitHub 点 com。` |
| `conv_zh_004` | 0.500 | `我想要查詢我的──戶餘額。` | **0.333** | `我想要查询我的賬戶餘額。` |
| `cs_edge_003` | 0.214 | `Docker Compose ���署了三个 microservice ── staging ───境。` | **0.024** | `Docker Compose 部署了三个 microservice 到 staging 环境。` |

U+FFFD (`���`) 和 Box Drawing (`──`) 乱码完全消失。`conv_zh_004` 流式模式仍有繁体字输出（`賬戶餘額` vs `账户余额`），这是模型本身的 token 选择问题，非编码层面的 bug。

---

## 经验总结

1. **Byte-level BPE tokenizer 不能逐 token 做 UTF-8 转换**。单个 token 的字节可能只是多字节字符的片段，必须累积所有字节后再做一次转换。

2. **`String::from_utf8_lossy` 是不可逆的破坏性操作**。不完整的 `[0xE5, 0x9C]` 一旦被替换为 U+FFFD，即使后续补齐了 `[0xB0]`，结果也是 `�°` 而非 `地`。

3. **流式 ASR 的 rollback 机制必须考虑字符编码边界**。token 级别的稳定边界和字节级别的 UTF-8 安全边界是两个不同的概念，需要分别处理。
