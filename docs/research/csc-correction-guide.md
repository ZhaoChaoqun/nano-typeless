# CSC（中文拼写纠错）技术调研与 Typeless 集成方案

**CSC = Chinese Spelling Correction（中文拼写纠错）**

*为 `nano-typeless` 项目编写 — 2026 年 2 月*

---

## 1. 什么是 CSC？为什么 ASR 需要它？

### 问题

语音识别（ASR）最常见的错误类型是**同音字/近音字替换**：

| ASR 输出（错误） | 正确文本 | 错误类型 |
|------------------|---------|---------|
| 今天新情很好 | 今天**心**情很好 | 同音字：新→心 |
| 我们在现了一个 bug | 我们**发**现了一个 bug | 近音字：在→发 |
| 请帮我查一下在线 | 请帮我查一下**再**现 | 同音字：在线→再现（上下文相关） |

这类错误的特点：
- **发音完全正确**，ASR 的声学模型没有听错
- 是**语言模型**在同音候选中选错了字
- 占中文 ASR 错误的 **70-80%**

### CSC 的解决思路

CSC 模型读入一段文本，**逐字判断**每个字是否需要替换为同音/近音的其他字：

```
输入: "今天新情很好"
       ↓ BERT 编码每个字的上下文语义
       ↓ 每个位置输出词表概率分布
       ↓ 位置 3："新"(0.12) vs "心"(0.87) → 替换为"心"
输出: "今天心情很好"
```

### CSC vs LLM 纠错的区别

| | CSC（BERT 类） | LLM 纠错（Qwen 等） |
|---|---|---|
| **模型类型** | 非自回归（NAR），一次前向传播 | 自回归（AR），逐 token 生成 |
| **模型大小** | ~100 MB (INT8) | ~300 MB - 1 GB (4-bit) |
| **推理延迟** | **15-30 ms** | **500-2000 ms** |
| **操作方式** | 逐字替换，不增删字符 | 重写整个句子 |
| **过度纠正风险** | 低（只替换，不创造） | **高**（会改变原意） |
| **同音字纠错** | 专长 | 一般 |
| **语法/语序纠错** | 不支持 | 支持 |
| **需要微调** | 已有开箱即用模型 | 必须微调，否则效果变差 |

**关键论文发现**：ASR-EC Benchmark（[arXiv:2412.03075](https://arxiv.org/abs/2412.03075)）证实，**未经微调的 LLM 做 ASR 纠错会让 CER 翻倍**（从 12.42% 恶化到 25.84%）。而 CSC 模型天然适合 ASR 的同音字错误场景。

---

## 2. CSC 模型选型

### 2.1 主流 CSC 模型对比

| 模型 | 架构 | 参数量 | 磁盘 (INT8) | Char-F1 | ONNX 支持 | 备注 |
|------|------|--------|------------|---------|----------|------|
| **macbert4csc-base** | MacBERT + SoftMasked | 102M | **98 MB** | **89.9** | ✅ 已有全套 | 首选：开箱即用 |
| ChineseBERT-for-csc | ChineseBERT + SCOPE | 200M | ~200 MB | 91.4 | ❌ | 额外字形/拼音特征，导出复杂 |
| ReaLiSe | BERT + 视觉+拼音 | 200M+ | ~200 MB | ~91 | ❌ | 同上，研究代码 |
| ECSpell | BERT + 错误一致掩码 | 110M | ~100 MB | ~90 | ❌ | 研究代码 |
| RBT6 + CSC 微调 | 6 层 BERT | 60M | **~65 MB** | ~85-88* | 需导出 | 需自行微调 |
| RBT3 + CSC 微调 | 3 层 BERT | 38M | **~40 MB** | ~80-83* | 需导出 | 最小但质量降低 |

*\* 标注估算值，需实际微调后测量*

### 2.2 选择：macbert4csc-base-chinese

选择理由：
1. **开箱即用**：在 SIGHAN 2015 数据集上训练好，无需微调
2. **ONNX 全套量化版已有**：ModelScope 上 `Xenova/macbert4csc-base-chinese` 提供 7 种格式
3. **98 MB INT8**：对一个 102M 参数的 BERT 模型来说非常紧凑
4. **NAR 推理**：一次前向传播处理整个句子，延迟固定 ~15-30ms
5. **项目兼容**：Typeless 已链接 `libonnxruntime`，无需引入新依赖

### 2.3 ModelScope 上的可用模型文件

仓库：[Xenova/macbert4csc-base-chinese](https://modelscope.cn/models/Xenova/macbert4csc-base-chinese)

| 文件 | 大小 | 精度 | 推荐 |
|------|------|------|------|
| `onnx/model.onnx` | 390 MB | FP32 | 基准 |
| `onnx/model_fp16.onnx` | 195 MB | FP16 | |
| **`onnx/model_int8.onnx`** | **98 MB** | **INT8** | **✅ 推荐** |
| `onnx/model_uint8.onnx` | 98 MB | UINT8 | |
| `onnx/model_q4.onnx` | 115 MB | 4-bit | |
| `onnx/model_q4f16.onnx` | 78 MB | 4-bit+FP16 | 最小 |
| `onnx/model_quantized.onnx` | 99 MB | 默认量化 | |
| `onnx/model_bnb4.onnx` | 110 MB | BNB 4-bit | |

---

## 3. MacBERT4csc 技术原理

### 3.1 MacBERT 基座

MacBERT（MLM as Correction BERT）是哈工大讯飞实验室（HFL）提出的 BERT 变体：

- **预训练改进**：用**同义词替换**代替 `[MASK]` token 做 MLM 训练，更贴近真实场景
- **架构**：标准 Transformer Encoder，12 层，768 维，12 头
- **词表**：21128 个中文字符 + 特殊 token

### 3.2 SoftMasked 纠错机制

macbert4csc 在 MacBERT 基座上加了 **Soft-Masked BERT** 机制（参考论文 [Soft-Masked BERT](https://arxiv.org/abs/2005.07421)）：

```
                    ┌──────────────┐
                    │   输入文本     │  "今天新情很好"
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  检测网络       │  每个位置输出错误概率
                    │  (BiGRU)      │  [0.02, 0.03, 0.91, 0.05, 0.01, 0.02]
                    └──────┬───────┘        ↑ "新"字错误概率 0.91
                           │
                    ┌──────▼───────┐
                    │  软掩码融合     │  将高错误概率位置的 embedding
                    │              │  与 [MASK] embedding 混合
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  纠正网络       │  BERT Encoder 在混合后的
                    │  (MacBERT)    │  embedding 上做 MLM 预测
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │   输出文本     │  "今天心情很好"
                    └──────────────┘
```

两阶段设计的好处：
- **检测网络**先标记可疑位置，避免 BERT 对正确字符做不必要的"纠正"
- **纠正网络**只需关注被标记的位置，提高精度、减少过度纠正

### 3.3 为什么适合 ASR 纠错

1. **同音字是 ASR 主要错误类型**：CSC 的训练数据大量包含同音字替换对
2. **字符级操作**：输入输出长度完全相同（不增不删），可控性强
3. **上下文理解**：12 层 Transformer 能理解"今天___情很好"中应该填"心"
4. **速度极快**：对比 LLM 的逐 token 生成，BERT 一次前向传播即可

### 3.4 局限性

| 能做 | 不能做 |
|------|--------|
| 同音字替换："新情"→"心情" | 插入缺失字："天好"→"天气好" |
| 近音字替换："在现"→"发现" | 删除多余字："我我想"→"我想" |
| 形近字替换："己经"→"已经" | 语序调整："好很天今"→"今天很好" |
| | 语法纠错："我想用 Rust 写一个 struct" 中的中英混合 |

对于 ASR 场景，**同音字替换覆盖了绝大多数错误**，以上局限在实际使用中影响不大。

---

## 4. SIGHAN 评测基准

SIGHAN（Special Interest Group on Chinese Language Processing）是中文拼写纠错的标准评测：

### 4.1 SIGHAN 2015 测试集结果

| 模型 | Detection-F1 | Correction-F1 | 备注 |
|------|-------------|--------------|------|
| macbert4csc-base | 89.91 | **87.05** | 本方案选用 |
| ChineseBERT-for-csc (SCOPE) | 91.39 | 88.73 | 更高但无 ONNX |
| BERT-base + fine-tune | ~85 | ~82 | 基线 |
| n-gram 语言模型 | ~60 | ~55 | 传统方法 |

### 4.2 评测指标解释

- **Detection-F1**：能否正确识别出哪个字是错的
- **Correction-F1**：能否将错字替换为正确的字
- **Sentence-level F1**：整个句子是否完全纠正正确（macbert4csc: 77.89）

---

## 5. Typeless 集成方案

### 5.1 整体架构

```
                    Typeless ASR Pipeline（当前）
                    ─────────────────────────────
    麦克风 → 音频捕获 → ASR Engine → 原始文本 → 标点处理 → 最终文本 → 粘贴
                                      │
                                      │  ← 新增 CSC 纠错
                                      ▼
                    Typeless ASR Pipeline（改进后）
                    ─────────────────────────────
    麦克风 → 音频捕获 → ASR Engine → 原始文本 → CSC 纠错 → 标点处理 → 最终文本 → 粘贴
                                                  │
                                          macbert4csc INT8
                                          (~15-30ms 延迟)
```

### 5.2 文件变更清单

| 文件 | 变更 | 说明 |
|------|------|------|
| `Sources/ChineseSpellingCorrector.swift` | **新增** | CSC 模型加载与推理（ONNX Runtime C API） |
| `Sources/BertTokenizer.swift` | **新增** | 中文 BERT 分词器（逐字符查 vocab.txt） |
| `Sources/SherpaOnnxManager.swift` | 修改 | 添加 CSC 模型下载管理 |
| `Sources/RecordingManager.swift` | 修改 | 在 ASR flush 后、标点处理前插入 CSC |
| `Sources/SettingsView.swift` | 修改 | 添加 CSC 模型下载/启用开关 |

### 5.3 推理流程

```swift
// ChineseSpellingCorrector.correctSpelling("今天新情很好")

// Step 1: 分词（字符级）
tokens = ["[CLS]", "今", "天", "新", "情", "很", "好", "[SEP]"]
input_ids = [101, 791, 1921, 3173, 2658, 2523, 1170, 102]

// Step 2: ONNX Runtime 前向传播
logits = session.run(input_ids)  // shape: [1, 8, 21128]

// Step 3: 每个位置取 argmax
output_ids = argmax(logits) = [101, 791, 1921, 2552, 2658, 2523, 1170, 102]
//                                              ↑ 3173(新) → 2552(心)

// Step 4: 解码
output = "今天心情很好"
```

### 5.4 性能预估

| 指标 | 预估值 |
|------|--------|
| 模型大小 (INT8) | 98 MB |
| 运行时内存增加 | ~150-200 MB |
| 单句推理延迟 (10-30 字) | 15-30 ms |
| 总流水线延迟增加 | ~20-30 ms |
| 用户感知 | **无感知**（远低于 100ms 阈值） |

### 5.5 与现有三个 ASR 引擎的配合

| 引擎 | CSC 价值 | 说明 |
|------|---------|------|
| **SenseVoice Nano** | ✅ 高 | CER 较高，同音字错误多，CSC 可显著改善 |
| **Streaming Paraformer** | ✅ 中 | 已有 ITN，但同音字仍是主要错误来源 |
| **Qwen3-ASR** | ⚠️ 低 | LLM 解码器自带较强语言理解，重复纠正可能反而引入错误 |

建议：默认对 SenseVoice Nano 和 Streaming Paraformer 启用 CSC，Qwen3-ASR 默认关闭。

---

## 6. 已知风险与缓解措施

### 6.1 过度纠正

macbert4csc 可能将正确的字"纠正"为错误的字，尤其是生僻词和专有名词。

**缓解**：
- 添加白名单机制：技术术语、人名等不做纠正
- 只替换置信度高于阈值（如 0.9）的位置
- 用户可在设置中关闭 CSC

### 6.2 中英混合文本

BERT 词表以中文为主，英文子词覆盖有限。"请帮我 review 这个 PR" 中的英文部分可能被错误替换。

**缓解**：
- 只对中文字符位置做纠正，跳过英文/数字/标点
- 或者用正则预处理，只提取中文部分送入模型

### 6.3 与标点模型的交互

CSC 应在标点处理**之前**运行：
- 标点模型可能在错别字基础上做出错误的断句
- 先纠错再加标点，能提高标点准确率

---

## 7. 参考资料

### 论文

- **Soft-Masked BERT** (ACL 2020): [arXiv:2005.07421](https://arxiv.org/abs/2005.07421) — SoftMasked 检测+纠正机制
- **SCOPE** (AAAI 2023): [arXiv:2210.10996](https://arxiv.org/abs/2210.10996) — 字形+拼音增强 CSC
- **ASR-EC Benchmark** (2024): [arXiv:2412.03075](https://arxiv.org/abs/2412.03075) — 首个中文 ASR 纠错基准，证实 LLM prompting 效果差
- **HyPoradise** (NeurIPS 2023): [arXiv:2309.15701](https://arxiv.org/abs/2309.15701) — LLM 用于 ASR 纠错
- **PY-GEC** (2024): [arXiv:2409.13262](https://arxiv.org/abs/2409.13262) — 拼音增强 ASR 纠错，CER 降低 22-25%

### 模型与工具

- **macbert4csc-base-chinese**: [HuggingFace](https://huggingface.co/shibing624/macbert4csc-base-chinese) | [ModelScope (ONNX)](https://modelscope.cn/models/Xenova/macbert4csc-base-chinese)
- **pycorrector**: [GitHub](https://github.com/shibing624/pycorrector) — 中文文本纠错工具包
- **Chinese-BERT-wwm**: [GitHub](https://github.com/ymcui/Chinese-BERT-wwm) — HFL 中文预训练模型
- **SIGHAN 2015 数据集**: 中文拼写纠错标准评测集
