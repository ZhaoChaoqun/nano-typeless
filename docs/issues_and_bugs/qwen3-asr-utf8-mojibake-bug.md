# Qwen3-ASR UTF-8 乱码 Bug 分析

## 现象

流式 ASR benchmark 中，部分中文字符被替换为 `�` (U+FFFD)：

```
期望: 我今天用Python写了一个API接口。
实际: 我今天用 Python ��了一个 API ��口。

期望: 在Rust里面用async await处理并发。
实际: 在 Rust 里面用 async await ��理并发。

期望: 用Docker Compose部署了3个microservice到staging环境。
实际: 用 Docker Compose ���署了三个 microservice �� staging ���境。
```

共 12 个 test case 出现乱码，全部是中英混合文本中的中文字符。

## 根因

GPT-2 byte-level BPE tokenizer 将 UTF-8 原始字节映射为 Unicode codepoint。一个 CJK 字符（3 字节 UTF-8）可能被 BPE 拆分到多个 token 中。

### 数据流

以"地"（U+5730, UTF-8: `E5 9C B0`）为例，假设 BPE 将其拆成两个 token：

```
Token A: 编码字节 [0xE5, 0x9C]  → vocab 中存储为 "ĥľ"
Token B: 编码字节 [0xB0]        → vocab 中存储为 "°"
```

### 问题代码（`tokenizer.rs:52-64`，修复前）

```rust
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
    String::from_utf8_lossy(&bytes).into_owned()  // ← 问题所在
}
```

### 损坏过程

```
Token A 解码:
  unicode_to_byte 查表 → bytes = [0xE5, 0x9C]
  String::from_utf8_lossy([0xE5, 0x9C])
    → [0xE5, 0x9C] 不是完整 UTF-8 序列
    → 替换为 U+FFFD (replacement character)
  id_to_text[A] = "�"           ← 原始字节永久丢失

Token B 解码:
  unicode_to_byte 查表 → bytes = [0xB0]
  String::from_utf8_lossy([0xB0])
    → [0xB0] 是 continuation byte，不合法
    → 替换为 U+FFFD
  id_to_text[B] = "�"           ← 原始字节永久丢失

拼接结果:
  "�" + "�" = "��"              ← 而非 "地"
```

### 核心问题

`String::from_utf8_lossy()` 在 **token 初始化阶段**就被调用，将不完整的 UTF-8 字节替换为 U+FFFD。这个替换是破坏性的——原始字节被永久丢弃，后续无法恢复。

正确做法是延迟 UTF-8 转换：先保存原始字节，在所有相邻 token 的字节拼接完成后再做 UTF-8 转换。

## 修复方案

分支 `fix/split-utf8-bpe-decoding` (commit `c86fae2`) 的修复：

### 1. 返回原始字节而非 String

```rust
// 修复前
fn decode_gpt2_token(token_str: &str, ...) -> String {
    // ...
    String::from_utf8_lossy(&bytes).into_owned()
}

// 修复后
fn decode_gpt2_token_bytes(token_str: &str, ...) -> Vec<u8> {
    // ...
    bytes  // 直接返回原始字节，不做 lossy 转换
}
```

### 2. 新增 `id_to_bytes` 存储原始字节

```rust
pub struct QwenTokenizer {
    id_to_text: Vec<Option<String>>,    // lossy UTF-8，仅供显示
    id_to_bytes: Vec<Option<Vec<u8>>>,  // 新增：原始字节
    // ...
}
```

### 3. 新增 `decode_bytes()` 方法

```rust
pub fn decode_bytes(&self, token_id: i32) -> &[u8] {
    match &self.id_to_bytes[token_id as usize] {
        Some(b) => b.as_slice(),
        None => b"",
    }
}
```

### 4. 流式管道使用字节累积

```rust
// transcribe.rs (patch 中的改动)
let mut result_bytes: Vec<u8> = Vec::new();   // 替代 result: String

// 累积原始字节
let piece_bytes = tokenizer.decode_bytes(token);
result_bytes.extend_from_slice(piece_bytes);

// 最终转换（所有字节已拼接完成）
String::from_utf8_lossy(&result_bytes)
```

### 修复后的解码流程

```
Token A: decode_bytes → [0xE5, 0x9C]     (保留原始字节)
Token B: decode_bytes → [0xB0]            (保留原始字节)

字节累积: [0xE5, 0x9C] ++ [0xB0] = [0xE5, 0x9C, 0xB0]
最终转换: String::from_utf8([0xE5, 0x9C, 0xB0]) → "地"  ✓
```

## 流式输出的 UTF-8 安全边界（已记录，暂未实施）

流式模式下，每次 chunk 推理后需要输出增量文本（delta）。理论上字节缓冲区末尾可能恰好在一个多字节字符中间，这时 `from_utf8_lossy` 会将不完整的尾字节替换为 U+FFFD。

**当前状态**：该问题目前在 benchmark 中没有实际触发案例。`decode_bytes()` 修复（`4d627d0`）已解决了绝大多数乱码。delta 边界截断只在以下条件同时满足时才会发生：

1. BPE token 本身跨越了 UTF-8 多字节边界（token 末尾包含不完整字节）
2. 该 token 恰好是某次 `stream_push_audio` 调用中最后一个被 emit 的 token

**如果后续出现乱码复现**，可以按以下方案排查和修复：

- 在 `StreamState` 中添加 `pending_delta_bytes: Vec<u8>` 字段
- 添加 `utf8_safe_boundary()` 函数，从末尾向前扫描找到最后一个完整 UTF-8 字符边界
- delta 返回前截断到安全边界，不完整的尾部字节保留到下次 push

```rust
fn utf8_safe_boundary(bytes: &[u8]) -> usize {
    let len = bytes.len();
    if len == 0 { return 0; }
    let mut i = len;
    while i > 0 && i > len.saturating_sub(4) {
        i -= 1;
        let b = bytes[i];
        if b & 0xC0 != 0x80 {
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

```
delta_bytes = [... 0xE5, 0x9C]     ← 末尾 2 字节是 "地" 的不完整序列
safe_end = len - 2                  ← utf8_safe_boundary 计算的安全边界
输出: delta_bytes[..safe_end]       ← 只输出完整字符
保留: [0xE5, 0x9C] → pending       ← 下次 push 时拼接
```

该修复曾提交为 `25a8061`，但因当前无实际触发案例被 revert（`f0e24e2`）。

## 涉及文件

| 文件 | 改动 | 状态 |
|------|------|------|
| `crates/qwen-asr/src/tokenizer.rs` | `decode_gpt2_token` → `decode_gpt2_token_bytes`，新增 `id_to_bytes`、`decode_bytes()` | ✅ 已合入 main (`4d627d0`) |
| `crates/qwen-asr/src/transcribe.rs` | `result: String` → `result_bytes: Vec<u8>`，`decode()` → `decode_bytes()` | ✅ 已合入 main (`4d627d0`) |
| `crates/qwen-asr/src/c_api.rs` | Streaming C FFI | ✅ 已合入 main (`b2c7dc5`) |
| `crates/qwen-asr/src/transcribe.rs` | `utf8_safe_boundary()`、`pending_delta_bytes` | ⏸ 暂缓，等遇到实际案例再加 |

## 状态

- [x] `fix/split-utf8-bpe-decoding` 已 merge 到 main (`4d627d0`)
- [x] `feat/streaming-c-api` 已 merge 到 main (`b2c7dc5`)
- [x] UTF-8 安全边界方案已记录，暂未实施（无实际触发案例）
