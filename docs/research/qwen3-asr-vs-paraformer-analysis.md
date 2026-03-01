# Qwen3-ASR vs Streaming Paraformer 准确度分析报告

*生成时间：2026-02-27*
*项目：Nano Typeless*

---

## 1. 问题描述

在 Typeless 中同时集成了 Qwen3-ASR-0.6B 和 Streaming Paraformer 两个 ASR 引擎后，实际测试中发现 Qwen3-ASR 的准确度并没有明显优于 Paraformer，与预期不符。本报告从**代码实现**、**模型架构**、**超参配置**、**公开基准测试**四个维度深入分析原因，并提供量化评估方案。

---

## 2. 代码层面分析：当前配置可能降低 Qwen3-ASR 质量

### 2.1 流式参数：为低延迟牺牲了准确度

`QwenASRRecognizer.swift:27-31` 中当前配置：

```swift
qwen_asr_stream_set_chunk_sec(engine, 1.5)        // 默认 2.0 → 改为 1.5
qwen_asr_stream_set_rollback(engine, 3)            // 默认 5   → 改为 3
qwen_asr_stream_set_unfixed_chunks(engine, 1)      // 默认 2   → 改为 1
qwen_asr_stream_set_max_new_tokens(engine, 24)     // 默认 32  → 改为 24
```

**这四个参数全部偏向低延迟，全部降低了准确度：**

| 参数 | 默认值 | 当前值 | 偏差方向 | 对准确度的影响 |
|------|--------|--------|----------|--------------|
| `chunk_sec` | 2.0s | 1.5s | -25% | 每次解码看到的音频上下文更少，边界词更容易出错 |
| `rollback` | 5 | 3 | -40% | 回退确认窗口缩小，chunk 边界处的 token 稳定性下降 |
| `unfixed_chunks` | 2 | 1 | -50% | 冷启动阶段输出更早但不够稳定，首几个词可能不准确 |
| `max_new_tokens` | 32 | 24 | -25% | 长句情况下可能被截断，丢失尾部内容 |

**影响量化估计（基于 Qwen3-ASR 论文 Table 8 的流式降级数据）**：
- 论文中 0.6B 模型在默认流式配置(`chunk_sec=2.0, rollback=5, unfixed_chunks=2`)下，CER 已经比离线高 26%
- 当前配置进一步激进化，预估额外增加 10-20% 相对 CER

### 2.2 线程数硬编码

`QwenASRRecognizer.swift:12`:
```swift
init?(modelDir: String, numThreads: Int32 = 4)
```

硬编码 4 线程。而 Streaming Paraformer 使用 2 线程（`SherpaOnnxOnlineRecognizer.swift:42`）。Qwen3-ASR 是 AR 模型，每个 token 需要顺序解码，线程数主要影响 encoder 和矩阵乘法速度，但不直接影响准确度。此项不是准确度问题的根因。

### 2.3 音频推送频率差异

两个引擎接收音频的方式不同：

**Streaming Paraformer** (`ASREngine.swift:115-128`):
```swift
// 每个 tap callback（~256ms @16kHz）立即接收 + 立即解码
recognizer.acceptWaveform(samples: samples)
while recognizer.isReady() { recognizer.decode() }
```

**Qwen3-ASR** (`ASREngine.swift:173-181`):
```swift
// 每个 tap callback（~256ms @16kHz）立即推送到 Rust 侧
_ = self.recognizer.pushAudio(samples: samples, finalize: false)
let fullText = self.recognizer.getResult()
```

Qwen3-ASR 的 Rust 内部会将小 chunk 积累到 `chunk_sec`（1.5s）后才执行一次推理。这个机制本身是正确的，但因为 `chunk_sec` 被缩小到 1.5s，每次推理的上下文比默认少 25%。

### 2.4 后处理管线差异

| 处理步骤 | Streaming Paraformer | Qwen3-ASR |
|----------|---------------------|-----------|
| ITN（数字转换） | ✅ `itn_zh_number.fst` | ❌ 内置（质量取决于模型本身） |
| CSC（纠错） | ✅ `macbert4csc` | ❌ 不需要 |
| 标点 | ✅ `CT-Transformer` | ✅ 内置 |

Paraformer 有额外的 CSC 纠错管线，可以修正同音字错误（如"新情" → "心情"），这给了它一定的后处理优势。而 Qwen3-ASR 的准确度完全依赖模型本身，没有后处理纠错。

---

## 3. 模型架构分析：为什么 0.6B 没有碾压 Paraformer？

### 3.1 架构对比

```
Qwen3-ASR-0.6B (Autoregressive)
┌──────────────┐    ┌──────────────────────┐
│ Audio Encoder │───▶│ Qwen3 LLM Decoder    │
│ (Transformer) │    │ (自回归, 逐 token 生成) │
└──────────────┘    └──────────────────────┘
参数量: ~481M, 模型文件: ~1.2GB

Streaming Paraformer (Non-Autoregressive)
┌──────────────────┐    ┌─────────┐    ┌──────────────────┐
│ Conformer Encoder │───▶│ CIF 对齐 │───▶│ NAR Decoder      │
│                  │    │         │    │ (单步并行生成全部) │
└──────────────────┘    └─────────┘    └──────────────────┘
参数量: 220M, 模型文件: ~216MB
```

### 3.2 关键认知：0.6B 在流式模式下的实际水平

根据 Qwen3-ASR 论文 (arXiv:2601.21337) Table 8：

| 模型 | 模式 | LibriSpeech clean | LibriSpeech other | Fleurs-zh | 平均 |
|------|------|:-:|:-:|:-:|:-:|
| Qwen3-ASR-**1.7B** | 离线 | 1.63 | 3.38 | 2.41 | **2.69** |
| Qwen3-ASR-**1.7B** | 流式 | 1.95 | 4.51 | 2.84 | **3.33** |
| Qwen3-ASR-**0.6B** | 离线 | 2.11 | 4.55 | 2.88 | **3.48** |
| Qwen3-ASR-**0.6B** | **流式** | 2.54 | **6.27** | **3.40** | **4.40** |

**0.6B 流式模式的降级非常显著**：
- 平均 WER/CER 比离线高 **26%**（3.48 → 4.40）
- 在嘈杂音频（LibriSpeech other）上降级最严重：4.55 → **6.27**（+37.8%）
- 中文（Fleurs-zh）: 2.88 → 3.40（+18%）

### 3.3 与 Paraformer-Large 的直接对比

| 基准 | Paraformer-Large (220M) | Qwen3-ASR-0.6B 流式 | 差距 |
|------|:-:|:-:|:-:|
| AISHELL-2 | 2.85 | ~3.15（离线）/ ~3.75（流式估算） | Paraformer 更好 |
| WenetSpeech net | 6.74 | 5.97（离线）/ ~7.1（流式估算） | 大致持平 |
| WenetSpeech meeting | 6.97 | 6.88（离线）/ ~8.2（流式估算） | Paraformer 更好 |

> **注**：Qwen3-ASR 论文未直接报告 AISHELL-2 和 WenetSpeech 的流式数据，上表流式数值是根据论文中其他数据集流式降级比例（~18-26%）估算的。

**关键结论**：**Qwen3-ASR-0.6B 在流式模式下，准确度与 Paraformer-Large 基本持平，甚至可能略差。** 只有 1.7B 版本在流式模式下才能稳定超过 Paraformer。

### 3.4 为什么 AR 模型在流式场景下优势缩小？

1. **上下文割裂**：AR 解码器在 chunk 边界处需要 rollback，rollback 窗口内的 token 是不确定的。NAR 模型的 CIF 对齐天然处理 chunk 边界，不存在此问题。

2. **LLM 语言模型优势被削弱**：Qwen3 的 LLM decoder 在离线模式下可以看到完整音频的全局信息进行预测，但流式模式每次只看 1.5-2s 的 chunk，LLM 的语义理解能力大打折扣。

3. **冷启动惩罚**：`unfixed_chunks=1` 意味着第一个 1.5s 的音频 chunk 被抑制输出，等同于丢弃了 1.5s 的上下文信息。

4. **小模型容量受限**：0.6B 参数（实际约 481M）中需要同时承载 audio encoder 和 LLM decoder，每个组件的容量都比专用模型小。Paraformer 的 220M 参数全部用于 ASR 任务，参数利用率更高。

---

## 4. 公开基准数据汇总

### 4.1 中文核心基准（CER %，越低越好）

| 模型 | 参数量 | 架构 | AISHELL-1 | AISHELL-2 | WenetSpeech net | WenetSpeech meeting |
|------|--------|------|:-:|:-:|:-:|:-:|
| Paraformer-Large | 220M | NAR | **1.68** | **2.85** | 6.74 | 6.97 |
| Qwen3-ASR-0.6B （离线） | 481M | AR | N/A | 3.15 | **5.97** | **6.88** |
| Qwen3-ASR-0.6B （流式） | 481M | AR | N/A | ~3.75* | ~7.1* | ~8.2* |
| Qwen3-ASR-1.7B （离线） | 1.7B | AR | N/A | **2.71** | **4.97** | **5.88** |
| Qwen3-ASR-1.7B （流式） | 1.7B | AR | N/A | ~3.2* | ~5.9* | ~7.0* |
| Whisper-large-v3 | 1.5B | AR | N/A | 5.06 | 9.86 | 19.11 |
| FunASR-MLT-Nano | - | NAR | N/A | N/A | 6.35 | N/A |

> *带星号为根据论文其他数据集流式降级比例估算

### 4.2 结论

- **Paraformer-Large 在 AISHELL-1/2 上表现极佳**（1.68/2.85），这些是干净、标准的普通话录制
- **Qwen3-ASR-0.6B 离线模式**在 WenetSpeech 上略好于 Paraformer，但差距不大
- **Qwen3-ASR-0.6B 流式模式**经过 18-26% 的降级后，与 Paraformer 基本持平
- 只有 **Qwen3-ASR-1.7B** 才能在流式模式下稳定超过 Paraformer

---

## 5. 综合诊断：为什么你感觉 Qwen3-ASR 没有更好

### 原因一级：流式降级 × 激进参数 = 实际水平与 Paraformer 持平

```
Qwen3-ASR-0.6B 理论准确度链：
  离线最佳 → 流式默认配置（-26%）→ 你的激进配置（再 -10~20%）
  = 最终准确度：与 Paraformer 持平甚至略差
```

### 原因二级：Paraformer 有后处理加持

```
Paraformer 管线：
  原始 ASR → ITN（数字转换）→ CSC（纠错）→ 标点
  = 最终文本质量被后处理拉高

Qwen3-ASR 管线：
  原始 ASR → 直接输出
  = 全靠模型本身，没有兜底
```

### 原因三级：使用场景的影响

- 如果你测试的句子主要是**短句、标准普通话**（类似 AISHELL），Paraformer 本身就擅长
- 如果你测试的是**长对话、嘈杂环境、方言**，Qwen3-ASR 1.7B 的优势会更明显
- 0.6B 版本在这些场景下优势不大

---

## 6. 优化建议

### 6.1 短期：调整流式参数提升准确度

```swift
// QwenASRRecognizer.swift — 「准确度优先」配置
qwen_asr_stream_set_chunk_sec(engine, 2.0)        // 恢复默认
qwen_asr_stream_set_rollback(engine, 5)            // 恢复默认
qwen_asr_stream_set_unfixed_chunks(engine, 2)      // 恢复默认
qwen_asr_stream_set_max_new_tokens(engine, 32)     // 恢复默认
```

**预期效果**：CER 降低 10-20%（相对），但首字延迟从 ~2.5s 增加到 ~5s。

或者折中方案：

```swift
// 「均衡」配置
qwen_asr_stream_set_chunk_sec(engine, 2.0)        // 恢复默认（最关键）
qwen_asr_stream_set_rollback(engine, 4)            // 略低于默认
qwen_asr_stream_set_unfixed_chunks(engine, 1)      // 保持低延迟
qwen_asr_stream_set_max_new_tokens(engine, 32)     // 恢复默认
```

### 6.2 中期：支持用户在 Settings 中选择「低延迟」/「高准确度」模式

在 `SettingsView.swift` 中为 Qwen3-ASR 增加模式选择：

| 模式 | chunk_sec | rollback | unfixed_chunks | max_new_tokens | 首字延迟 |
|------|:-:|:-:|:-:|:-:|:-:|
| 低延迟 | 1.5 | 3 | 1 | 24 | ~2.5s |
| 均衡（默认） | 2.0 | 4 | 1 | 32 | ~3s |
| 高准确度 | 3.0 | 6 | 2 | 48 | ~7s |

### 6.3 长期：考虑 Qwen3-ASR-1.7B

如果设备算力允许（M 系列 Mac），1.7B 版本在流式模式下准确度显著优于 0.6B：
- AISHELL-2: 3.75 → 3.2（估算）
- WenetSpeech net: 7.1 → 5.9（估算）
- 首字延迟也更一致（更大的 decoder 更稳定）

代价：模型 ~3.4GB，CPU 内存峰值 ~5.3GB。

---

## 7. 量化评估方案

### 7.1 已有测试基础设施

项目中已有完整的评估体系：

- **测试文件**：109 个测试用例（`TypelessTests/`）
- **FuzzyASRMatcher**：CER 计算 + Levenshtein 距离 + 文本归一化
- **测试数据**：
  - `tests/fixtures/corpus.json`：35 条 Edge-TTS 合成语料
  - `tests/fixtures/real_manifest.json`：41 条真实数据（AISHELL、MINDS-14、ASCEND、WenetSpeech）

### 7.2 建议：新建 A/B 对比评估脚本

编写一个 Python 脚本，对同一组音频文件分别调用两个引擎，输出逐条 CER 和汇总统计：

```
评估维度：
1. 整体 CER/WER（按数据集分组）
2. 按句子长度分桶
3. 按语言类型（纯中文 / 中英混合 / 纯英文）
4. 按音频来源（AISHELL / WenetSpeech / Edge-TTS / ASCEND）
5. 技术词汇命中率
6. 标点准确率（F1 score）
```

### 7.3 具体执行步骤

**Step 1**: 准备测试音频（已完成）

```bash
# 已有的合成语料
ls tests/fixtures/audio/edge_tts/

# 下载真实数据（如果还没下载）
uv run --with 'datasets[audio]' --with soundfile --with scipy --with edge-tts \
    python scripts/download_real_test_data.py
```

**Step 2**: 编写对比评估脚本 `scripts/benchmark_engines.py`

需要实现：
1. 用 Qwen3-ASR 的 C API（通过 Python ctypes 加载 `libqwen_asr.dylib`）对所有音频跑一遍
2. 用 sherpa-onnx Python SDK 对所有音频跑 Streaming Paraformer
3. 计算并输出 CER 对比表

**Step 3**: 对比不同配置的影响

| 评估场景 | chunk_sec | rollback | unfixed_chunks | max_new_tokens |
|----------|:-:|:-:|:-:|:-:|
| 当前配置 | 1.5 | 3 | 1 | 24 |
| 默认配置 | 2.0 | 5 | 2 | 32 |
| 高准确度 | 3.0 | 8 | 3 | 48 |
| 离线模式 | N/A | N/A | N/A | N/A |

**Step 4**: 输出报告格式

```
=== Qwen3-ASR vs Streaming Paraformer 准确度对比报告 ===

配置: Qwen3-ASR (chunk=1.5, rollback=3) vs Paraformer (greedy + ITN + CSC + punct)

┌──────────────────────┬────────────┬─────────────┬──────────┐
│ 数据集               │ Qwen3 CER  │ Paraformer  │ 差异     │
│                      │            │ CER         │          │
├──────────────────────┼────────────┼─────────────┼──────────┤
│ AISHELL-1 (8条)      │ 4.2%       │ 3.1%        │ +1.1%    │
│ Edge-TTS 中文 (10条)  │ 2.8%       │ 3.5%        │ -0.7%    │
│ ASCEND 混合 (10条)   │ 8.5%       │ 9.2%        │ -0.7%    │
│ WenetSpeech (10条)   │ 7.1%       │ 7.8%        │ -0.7%    │
│ ---                  │            │             │          │
│ 整体平均              │ 5.65%      │ 5.90%       │ -0.25%   │
└──────────────────────┴────────────┴─────────────┴──────────┘
```

---

## 8. 总结

| 维度 | 结论 |
|------|------|
| **Qwen3-ASR-0.6B 比 Paraformer 更好吗？** | 离线模式在部分基准上略好，流式模式基本持平 |
| **为什么你感觉差不多？** | 0.6B 流式降级 26% + 你的激进参数进一步降低质量 + Paraformer 有 CSC 后处理加持 |
| **最高性价比的改善方法** | 将 `chunk_sec` 恢复为 2.0，`max_new_tokens` 恢复为 32 |
| **想要明显超过 Paraformer** | 需要 Qwen3-ASR-1.7B，或者离线模式 |
| **建议的定位** | Paraformer = 低延迟首选，Qwen3-ASR = 准确度优先选项（需恢复默认参数） |

---

*参考文献：*
- *Qwen3-ASR: Towards End-to-End ASR via LLM (arXiv:2601.21337)*
- *Paraformer: Fast and Accurate Parallel Transformer for Non-autoregressive End-to-End Speech Recognition (arXiv:2206.08317)*
- *sherpa-onnx Issue #3110: Qwen3-ASR support request*
