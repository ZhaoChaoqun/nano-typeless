# CSC 中文拼写纠错 Bug 分析报告

*2026-03-01*

---

## 1. 问题现象

CSC 模型将正确文本全部替换成乱码：

```
输入: "我今天需要1些你的帮助"
输出: "戒仍夭震咒1许谎皙帮势"
```

9 个中文字中有 9 个被"纠正"为错误字符。

---

## 2. 根因分析

### 2.1 核心 Bug: `vocabSize` 计算错误

**文件**: `Sources/BertTokenizer.swift:41`

```swift
self.vocabSize = t2i.count  // = 21127 (错误)
```

`vocab.txt` 有 21129 行，其中：
- 第 343 行是 Unicode 行分隔符 `\u2028`（被 `.trimmingCharacters(in: .whitespaces)` 清除后变为空，跳过）
- 第 21128 行是空行（末尾换行符产生）

因此 `t2i.count` = 21129 - 2 = **21127**。

但模型输出的 logits shape 是 `[1, seqLen, 21128]`，**最后一维是 21128**。

### 2.2 错误传播机制

`vocabSize` 在 `ChineseSpellingCorrector.swift:225` 用于计算 logits 的内存偏移：

```swift
let logitsOffset = i * vocabSize  // i * 21127，但应为 i * 21128
```

由于步长少了 1，每个 token 位置的 logits 读取起始地址都会向前偏移 `i` 个 float：

| 位置 | 字符 | 正确偏移 | 实际偏移 | 错位量 |
|------|------|----------|----------|--------|
| i=1 | 我 | 21128 | 21127 | -1 |
| i=2 | 今 | 42256 | 42254 | -2 |
| i=3 | 天 | 63384 | 63381 | -3 |
| i=4 | 需 | 84512 | 84508 | -4 |
| ... | ... | ... | ... | ... |
| i=11 | 助 | 232408 | 232397 | -11 |

### 2.3 错误结果验证

错位导致 argmax 在错误的 logit 区间取最大值，结果命中邻近的 token ID：

| 正确字 | 正确ID | 错误字 | 错误ID | ID差值 | 位置偏移 |
|--------|--------|--------|--------|--------|----------|
| 我 | 2769 | 戒 | 2770 | +1 | i=1, 偏移1 |
| 今 | 791 | 仍 | 793 | +2 | i=2, 偏移2 |
| 天 | 1921 | 夭 | 1924 | +3 | i=3, 偏移3 |
| 需 | 7444 | 震 | 7448 | +4 | i=4, 偏移4 |
| 助 | 1221 | 势 | 1232 | +11 | i=11, 偏移11 |

前几个字符的 ID 差值与位置偏移完全吻合，确认 Bug。

### 2.4 为什么 logit 差值阈值检查没有拦住？

由于 logits 被读错位置，每个位置的 21127 个 logit 值来自错误的内存区域。原始 token 的 logit 值也是从错误位置读取的，和 argmax 值一样都来自错误的 logits 行。在错误的数据上计算 logit 差值没有意义，无法起到过滤作用。

### 2.5 Python 验证

使用 `onnxruntime` Python 版验证：模型对 "我今天需要1些你的帮助" 的推理输出中，所有位置的 argmax 都等于原始 token ID（即不需要纠正），完全正确。确认 Bug 在 Swift 侧。

---

## 3. 修复计划

### 修改 1: BertTokenizer 使用正确的 vocabSize（核心修复）

**文件**: `Sources/BertTokenizer.swift`

**问题**: `vocabSize = t2i.count` 会因跳过空行导致值偏小。

**方案**: 不使用 `t2i.count`，改用 `lines` 数组中有效的最大行号 + 1（因为 token ID = 行号），这等于文件的实际非空最大 ID + 1。更稳健的做法是直接从模型获取 vocab 维度，但最简单的修复是：`vocabSize` 应基于行数而非字典 count。

```swift
// 修改前
self.vocabSize = t2i.count  // 21127 (跳过了空行)

// 修改后：取所有有效 token 中最大的 ID + 1
// 这样即使中间有空行，vocabSize 仍然和模型的 vocab_size 维度一致
self.vocabSize = (t2i.values.max() ?? 0) + 1  // 21128 (会包含空行占的 ID 位)
```

但更直接可靠的方式是不跳过空行，保证行号和 ID 严格对应：

```swift
// 另一个方案：不跳过空行，使用总行数（排除末尾空行）
let lines = content.components(separatedBy: .newlines)
var maxId: Int32 = 0
for (index, line) in lines.enumerated() {
    let token = line.trimmingCharacters(in: .whitespaces)
    guard !token.isEmpty else { continue }
    let id = Int32(index)
    t2i[token] = id
    i2t[id] = token
    maxId = max(maxId, id)
}
self.vocabSize = Int(maxId) + 1  // = 21128
```

**推荐方案**: 使用 `maxId + 1`，因为这最准确反映了模型期望的词表大小。

### 修改 2: 添加 vocabSize 一致性校验（可选但推荐）

**文件**: `Sources/ChineseSpellingCorrector.swift`

在模型初始化后，查询模型输出的 shape 来验证 vocabSize 是否一致：

```swift
// 在 init 中，session 创建成功后：
// 查询输出 shape 的最后一维，与 tokenizer.vocabSize 比较
// 如果不匹配，打印警告日志
```

这是一个安全网，防止类似问题再次发生。

---

## 4. 影响范围

- **受影响引擎**: SenseVoice Nano 和 Streaming Paraformer（`needsPunctuation = true`）
- **不受影响**: Qwen3-ASR（不经过 CSC 处理）
- **严重程度**: CSC 纠错完全失效，会把正确文本改成乱码
- **修复复杂度**: 低，只需改一行代码

---

## 5. 后续优化建议

1. **添加调试日志**: 在 CSC 初始化时打印 `vocabSize`，便于后续排查
2. **添加 sanity check**: 如果 CSC 单次纠正数量过多（如 >50% 的字被改），应丢弃纠正结果并返回原文
3. **单元测试**: 为 BertTokenizer 添加测试，验证 vocabSize 与已知正确值一致
