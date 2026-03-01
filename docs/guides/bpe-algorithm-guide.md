# BPE (Byte Pair Encoding) 算法深入浅出

## 目录

1. [为什么需要 BPE](#1-为什么需要-bpe)
2. [BPE 核心思想：从字符到子词](#2-bpe-核心思想从字符到子词)
3. [BPE 训练过程](#3-bpe-训练过程)
4. [BPE Encode（编码）](#4-bpe-encode编码)
5. [BPE Decode（解码）](#5-bpe-decode解码)
6. [GPT-2 的 Byte-Level BPE](#6-gpt-2-的-byte-level-bpe)
7. [Qwen3-ASR 的实际实现](#7-qwen3-asr-的实际实现)
8. [UTF-8 乱码问题的本质](#8-utf-8-乱码问题的本质)

---

## 1. 为什么需要 BPE

在自然语言处理中，模型需要将文本转换为数字（token ID）才能处理。最直接的方式有两种，但都有明显问题：

### 方案 A：按字符切分

```
"unhappiness" → ["u", "n", "h", "a", "p", "p", "i", "n", "e", "s", "s"]
                 11 个 token
```

- 词汇表小（英文只有 26+26+10+标点 ≈ 100 个 token）
- 但序列太长，模型难以学习长距离语义
- "un" 表示否定，被拆成了独立的 "u" 和 "n"，语义丢失

### 方案 B：按整词切分

```
"unhappiness" → ["unhappiness"]
                 1 个 token
```

- 序列短，但词汇表巨大（英文有 50 万+ 词形）
- 遇到新词（如 "ChatGPT"）直接变成 `[UNK]`（未知词）
- 无法利用词根词缀的共享语义

### BPE：两全其美的子词方案

```
"unhappiness" → ["un", "happiness"]  或  ["un", "happ", "iness"]
                 2~3 个 token
```

- 词汇表适中（通常 3 万 ~ 15 万）
- 高频词保持完整，低频词拆为有意义的子词
- 永远不会遇到未知词（最差情况退化为逐字符）

---

## 2. BPE 核心思想：从字符到子词

BPE 的本质是一种**压缩算法**，最早由 Philip Gage 在 1994 年提出，用于数据压缩。2016 年被引入 NLP 领域用于分词。

核心思想只有一句话：

> **反复找到语料中最频繁出现的相邻符号对，将其合并为新符号。**

---

## 3. BPE 训练过程

训练是在**大规模文本语料**上离线完成的，产出两个文件：
- `vocab.json` — 词汇表（token 字符串 → ID 的映射）
- `merges.txt` — 合并规则（按优先级排序）

### 完整示例

假设训练语料只有 5 个词（括号内为频次）：

```
语料:  "low"(5)  "lower"(2)  "newest"(6)  "widest"(3)  "new"(2)
```

**第 0 步：初始化——将每个词拆成字符序列**

```
l o w       ×5
l o w e r   ×2
n e w e s t ×6
w i d e s t ×3
n e w       ×2
```

初始词汇表：`{l, o, w, e, r, n, s, t, i, d}`（10 个字符）

**第 1 步：统计所有相邻字符对的频次**

```
(l, o) → 5+2 = 7
(o, w) → 5+2 = 7
(w, e) → 2+6+2 = 10    ← 在 "lower" 中 w 后面没有 e？不对，有的
                           lower: l-o-w-e-r, 所以 (w,e) 出现在 lower, newest, new
(e, r) → 2
(n, e) → 6+2 = 8
(e, w) → 6+2 = 8        ← 等等，注意方向：newest = n-e-w-e-s-t
(e, s) → 6+3 = 9        ← 最高频！
(s, t) → 6+3 = 9        ← 并列最高
(w, i) → 3
(i, d) → 3
(d, e) → 3
```

选择频次最高的对 `(e, s)` → 合并为 `es`，写入 merges.txt 第 1 行。

> merges.txt 第 1 行：`e s`

**第 2 步：替换语料中所有 (e, s) → es**

```
l o w       ×5
l o w e r   ×2
n e w es t  ×6        ← e+s 变成 es
w i d es t  ×3        ← e+s 变成 es
n e w       ×2
```

词汇表：`{l, o, w, e, r, n, s, t, i, d, es}`

**第 3 步：重新统计，继续合并**

```
(es, t) → 6+3 = 9     ← 最高频！
(n, e)  → 6+2 = 8
...
```

合并 `(es, t)` → `est`

> merges.txt 第 2 行：`es t`

```
l o w       ×5
l o w e r   ×2
n e w est   ×6         ← es+t 变成 est
w i d est   ×3         ← es+t 变成 est
n e w       ×2
```

**继续迭代...**

```
第 4 轮: (n, e) → ne      merges: "n e"
第 5 轮: (ne, w) → new    merges: "ne w"
第 6 轮: (l, o) → lo      merges: "l o"
第 7 轮: (lo, w) → low    merges: "lo w"
第 8 轮: (new, est) → newest  merges: "new est"
...
```

**训练结束条件：** 词汇表达到预设大小（如 Qwen 的 151,936 个 token）时停止。

### 最终产出

**vocab.json**（token → ID 映射）：
```json
{
  "l": 0, "o": 1, "w": 2, "e": 3, "r": 4,
  "n": 5, "s": 6, "t": 7, "i": 8, "d": 9,
  "es": 10, "est": 11, "ne": 12, "new": 13,
  "lo": 14, "low": 15, "newest": 16, ...
}
```

**merges.txt**（合并规则，按训练顺序）：
```
e s
es t
n e
ne w
l o
lo w
new est
...
```

merges.txt 的行号就是优先级（rank）——越靠前的规则优先级越高。

---

## 4. BPE Encode（编码）

编码是将文本转为 token ID 序列的过程。

### 算法步骤

```
输入: "newest"
目标: 转为 token ID 序列
```

**第 1 步：拆成最小单元（逐字符）**

```
符号列表: ["n", "e", "w", "e", "s", "t"]
```

**第 2 步：查找所有相邻对在 merges.txt 中的 rank**

```
("n","e") → rank 2 (merges 第 3 行)
("e","w") → 不在 merges 中 → rank ∞
("w","e") → 不在 merges 中 → rank ∞
("e","s") → rank 0 (merges 第 1 行)    ← 最小 rank！
("s","t") → 不在 merges 中（它们是通过 es+t 合并的，不是 s+t）
```

**第 3 步：执行 rank 最小的合并**

```
合并 ("e","s") → "es"
符号列表: ["n", "e", "w", "es", "t"]
```

**第 4 步：重复，直到无法继续**

```
查找相邻对:
("n","e")  → rank 2
("e","w")  → rank ∞
("w","es") → rank ∞
("es","t") → rank 1    ← 最小！

合并 ("es","t") → "est"
符号列表: ["n", "e", "w", "est"]
```

```
查找相邻对:
("n","e")   → rank 2    ← 最小！
("e","w")   → rank ∞
("w","est") → rank ∞

合并 ("n","e") → "ne"
符号列表: ["ne", "w", "est"]
```

```
查找相邻对:
("ne","w")   → rank 3    ← 最小！
("w","est")  → rank ∞

合并 ("ne","w") → "new"
符号列表: ["new", "est"]
```

```
查找相邻对:
("new","est") → rank 6    ← 有效

合并 ("new","est") → "newest"
符号列表: ["newest"]
```

无法继续（只剩一个符号），结束。

**第 5 步：查 vocab.json 得到 ID**

```
"newest" → ID 16

最终: "newest" → [16]
```

### 如果遇到词汇表中没有的合并结果？

```
"newish" → 拆分 → ["n","e","w","i","s","h"]
→ 合并 e+s → ["n","e","w","i","sh"]... 不对，merges里没有 i+s
→ 实际: 合并 n+e → ["ne","w","i","s","h"]
→ 合并 ne+w → ["new","i","s","h"]
→ 没有更多可合并 → 查 vocab: "new"=13, "i"=8, "s"=6, "h"=...

结果: "newish" → [13, 8, 6, h的ID]
```

BPE 保证任何文本都能编码——最差退化为逐字符。

### QwenASR 代码中的实现

对应 `tokenizer.rs:221-262` 的 `encode_bpe_word()` 方法：

```rust
fn encode_bpe_word(&self, mapped: &str) -> Option<Vec<i32>> {
    // 第 1 步：拆成单字符符号
    let mut syms = split_utf8_symbols(mapped);

    // 第 2-4 步：反复合并 rank 最小的相邻对
    while syms.len() > 1 {
        let mut best_rank = i32::MAX;
        let mut best_i = -1i32;

        // 扫描所有相邻对，找 rank 最小的
        for i in 0..syms.len() - 1 {
            let pair = format!("{} {}", syms[i], syms[i + 1]);
            if let Some(&rank) = self.merge_map.get(&pair) {
                if rank < best_rank {
                    best_rank = rank;
                    best_i = i as i32;
                }
            }
        }

        if best_i < 0 { break; }  // 没有可合并的对了

        // 执行合并
        let i = best_i as usize;
        let merged = format!("{}{}", syms[i], syms[i + 1]);
        syms[i] = merged;
        syms.remove(i + 1);
    }

    // 第 5 步：查 vocab 得到 ID
    let mut ids = Vec::new();
    for sym in &syms {
        let id = self.vocab_map.get(sym.as_str()).copied()?;
        ids.push(id);
    }
    Some(ids)
}
```

---

## 5. BPE Decode（解码）

解码是编码的逆过程，将 token ID 序列转回文本。

### 算法

解码非常简单——**不需要 merges.txt，只需 vocab.json**：

```
输入: [13, 11]
查表: 13 → "new", 11 → "est"
拼接: "new" + "est" = "newest"
```

就是逐个查表，然后拼接字符串。

### QwenASR 代码中的实现

对应 `tokenizer.rs:201-209`：

```rust
pub fn decode(&self, token_id: i32) -> &str {
    match &self.id_to_text[token_id as usize] {
        Some(s) => s.as_str(),
        None => "",
    }
}
```

### 为什么 decode 这么简单？

因为 vocab.json 在加载时已经把每个 token 的字符串表示预计算好了。encode 时的合并过程是确定性的，所以同一个 token ID 永远对应同一个字符串片段，直接查表即可。

---

## 6. GPT-2 的 Byte-Level BPE

上面描述的是经典 BPE。GPT-2 引入了一个关键变体：**Byte-Level BPE**，Qwen3-ASR 也使用这种方案。

### 经典 BPE 的局限

经典 BPE 以 Unicode 字符为最小单元。问题：

- Unicode 有 14 万+ 字符（CJK、emoji、阿拉伯语...），初始词汇表就巨大
- 极罕见的字符可能不在训练语料中，变成 `[UNK]`

### Byte-Level BPE 的解决方案

**将最小单元从 "Unicode 字符" 降为 "字节"。**

任何文本在内存中都是一串字节（0x00~0xFF），所以：
- 初始词汇表只有 **256** 个 token（每个字节一个）
- **永远不会遇到未知符号**——任何数据都是字节组成的

### 问题：字节不可打印

字节 0x00~0x1F（控制字符）、0x7F（DEL）等无法显示在 vocab.json 中。

### GPT-2 的解决方案：字节-Unicode 映射

GPT-2 定义了一个 256 → 256 的可逆映射，将每个字节映射为一个可打印的 Unicode 字符：

```
字节 0x41 ('A')  →  Unicode 'A'   (可打印字节保持不变)
字节 0x20 (' ')  →  Unicode 'Ġ'   (空格、控制字符映射到特殊 Unicode)
字节 0x0A ('\n') →  Unicode 'Ċ'   (换行符映射到另一个字符)
字节 0xE5        →  Unicode 'å'   (高位字节映射到扩展拉丁)
```

这样 vocab.json 的 key 都是可打印字符串，但它们实际代表的是**原始字节序列**。

### QwenASR 代码中的实现

对应 `tokenizer.rs:6-32` 的 `init_gpt2_mapping()`：

```rust
fn init_gpt2_mapping() -> ([i32; 256], [i32; 512]) {
    let mut byte_to_unicode = [0i32; 256];

    let mut n = 0i32;
    for b in 0..256i32 {
        // 可打印字节（33-126, 161-172, 174-255）映射到自身
        let is_normal = (b >= 33 && b <= 126)
            || (b >= 161 && b <= 172)
            || (b >= 174 && b <= 255);

        if is_normal {
            byte_to_unicode[b as usize] = b;      // 'A' → 65 → 'A'
        } else {
            byte_to_unicode[b as usize] = 256 + n; // 0x00 → 256, 0x01 → 257, ...
            n += 1;
        }
    }
    // ... 同时构建反向映射 unicode_to_byte
}
```

### Encode 流程（Byte-Level）

```
输入: "地"

第 1 步: 转为 UTF-8 字节
  "地" → [0xE5, 0x9C, 0xB0]

第 2 步: 每个字节通过 GPT-2 映射转为 Unicode 符号
  0xE5 → 'å'
  0x9C → 'Ľ'  (举例，具体取决于映射表)
  0xB0 → '°'

第 3 步: 对 Unicode 符号序列执行 BPE 合并
  ["å", "Ľ", "°"] → 查 merges.txt → 可能合并为 ["åĽ", "°"] 或 ["åĽ°"]

第 4 步: 查 vocab.json 得到 ID
  "åĽ°" → ID 12345  (如果整体在词汇表中)
  或
  "åĽ" → ID 6789, "°" → ID 111  (如果被拆成两个 token)
```

### Decode 流程（Byte-Level）

```
输入: token ID 6789

第 1 步: 查 vocab.json → "åĽ"

第 2 步: 每个 Unicode 字符通过反向映射转为字节
  'å' → 0xE5
  'Ľ' → 0x9C

第 3 步: 得到字节序列 [0xE5, 0x9C]

第 4 步: 转为 UTF-8 字符串
  [0xE5, 0x9C] → ??? 这是不完整的 UTF-8！
  → String::from_utf8_lossy → "�"  ← BUG 就在这里！
```

---

## 7. Qwen3-ASR 的实际实现

### 两个关键文件

| 文件 | 内容 |
|------|------|
| `vocab.json` | 151,936 个 token 的映射（GPT-2 Unicode 字符串 → ID） |
| `merges.txt` | ~15 万行合并规则 |

### Encode 完整调用链

```
encode("地球")
  │
  ├─ text_to_bpe_unicode("地球")     // tokenizer.rs:68
  │    将 UTF-8 字节逐个映射为 GPT-2 Unicode 字符
  │    "地球" → [E5,9C,B0,E7,90,83] → "åĽ°çŃĥ"  (伪示例)
  │
  └─ encode_bpe_word("åĽ°çŃĥ")      // tokenizer.rs:221
       拆分: ["å","Ľ","°","ç","Ń","ĥ"]
       合并: 根据 merges.txt 反复合并
       查表: 合并后的每个 symbol → vocab.json → token ID
       返回: [token_id_1, token_id_2, ...]
```

### Decode 完整调用链

```
decode(token_id)
  │
  └─ 查 id_to_text[token_id]         // tokenizer.rs:201
       这是加载 vocab.json 时预计算的:
       vocab key "åĽ°" → decode_gpt2_token() → 字节 [E5,9C,B0] → "地"
       存储在 id_to_text 中供直接查询
```

### 加载过程（一次性）

```
QwenTokenizer::load("vocab.json")    // tokenizer.rs:130
  │
  ├─ 解析 vocab.json: {"åĽ°çŃĥ": 12345, ...}
  │
  ├─ 对每个 (key, id):
  │    decode_gpt2_token("åĽ°çŃĥ")   // 反向映射回字节，再转 UTF-8
  │    → id_to_text[12345] = "地球"   // 预存解码结果
  │    → vocab_map["åĽ°çŃĥ"] = 12345  // 正向查表供 encode 用
  │
  └─ 解析 merges.txt:
       "å Ľ" → rank 0
       "åĽ °" → rank 1
       ...
       → merge_map["å Ľ"] = 0
       → merge_map["åĽ °"] = 1
```

---

## 8. UTF-8 乱码问题的本质

现在可以完整理解 PR #12 修复的问题了。

### BPE 不关心字符边界

BPE 合并发生在 **GPT-2 Unicode 符号层面**，每个符号对应一个字节。合并边界完全由训练语料中的频率决定，与 UTF-8 字符边界无关。

```
"地" 的 UTF-8: [E5, 9C, B0] → GPT-2 符号: [å, Ľ, °]

BPE 可能把它合并为:
  情况 A: [åĽ°]     → 1 个 token，完整包含 "地" 的 3 字节    ✓
  情况 B: [åĽ] [°]  → 2 个 token，拆在字节边界                ✗ 潜在问题
  情况 C: [å] [Ľ°]  → 2 个 token，拆在另一个字节边界          ✗ 潜在问题
```

情况 B 和 C 并不罕见——当某个字节组合在训练语料中更频繁地与其他上下文共现时，BPE 就会这样拆分。

### 完整的乱码产生过程

以 ASR 解码 "在大地上" 为例，假设 BPE 把 "地" 拆成了两个 token：

```
ASR Decoder 生成 token 序列:
  [..., token_A("在"), token_B("大"), token_C([E5,9C]), token_D([B0,E4,B8]), token_E("上"), ...]
                                       ↑ "地"的前2字节    ↑ "地"的第3字节+"上"的前2字节

逐 token 解码（旧方式）:
  token_A → "在"     ← 完整字符  ✓
  token_B → "大"     ← 完整字符  ✓
  token_C → [E5,9C] → from_utf8_lossy → "�"   ← 2字节不够组成汉字！
  token_D → [B0,E4,B8] → from_utf8_lossy → "�" + 不完整  ← 也坏了
  token_E → "上"     ← 如果碰巧完整  ✓

最终输出: "在大��上"   ← 乱码！
```

### 修复后的过程

```
逐 token 解码（新方式，字节累积）:
  token_A → bytes [E5,9C,A8]           → 累积: [E5,9C,A8]
  token_B → bytes [E5,A4,A7]           → 累积: [E5,9C,A8, E5,A4,A7]
  token_C → bytes [E5,9C]              → 累积: [..., E5,9C]
  token_D → bytes [B0,E4,B8]           → 累积: [..., E5,9C,B0, E4,B8]
  token_E → bytes [8A]                 → 累积: [..., E4,B8,8A]

最终一次性转 UTF-8:
  [E5,9C,A8, E5,A4,A7, E5,9C,B0, E4,B8,8A]
   在(3B)    大(3B)    地(3B)    上(3B)

输出: "在大地上"   ← 正确！
```

### 关键总结

```
┌─────────────────────────────────────────────────────────┐
│                    BPE 的分层结构                        │
│                                                         │
│  文本层:     "在"    "大"    "地"         "上"           │
│              │       │     ╱    ╲        │              │
│  字节层:    E5 9C A8│E5 A4 A7│E5 9C│B0 E4 B8│8A         │
│              │       │       │     │       │            │
│  BPE Token: [tok_A] [tok_B] [tok_C][tok_D] [tok_E]     │
│                                                         │
│  注意: BPE token 边界 ≠ UTF-8 字符边界                   │
│       tok_C 只有 "地" 的前 2 字节                        │
│       tok_D 有 "地" 的最后 1 字节 + "上" 的前 2 字节      │
│                                                         │
│  所以: decode 时不能逐 token 转 UTF-8，必须先拼字节       │
└─────────────────────────────────────────────────────────┘
```

---

## 附录：BPE 变体对比

| 变体 | 最小单元 | 代表模型 | 初始词汇 |
|------|---------|---------|---------|
| 经典 BPE | Unicode 字符 | 早期 NMT | 数千~数万 |
| Byte-Level BPE | 字节 | GPT-2, Qwen, LLaMA | 256 |
| WordPiece | 子词（似然最大化） | BERT | - |
| SentencePiece (Unigram) | 子词（概率模型） | T5, mBART | - |
| Tiktoken | Byte-Level BPE (优化实现) | GPT-3.5/4 | 256 |

Qwen3-ASR 使用的是与 GPT-2 相同的 Byte-Level BPE，词汇表大小为 **151,936** 个 token。
