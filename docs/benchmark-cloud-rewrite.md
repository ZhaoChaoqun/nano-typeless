# Cloud Rewrite vs Local Rewrite 对比评估报告

*生成时间：2026-03-09 16:33*
*测试集：4 条音频（corpus.json + real_manifest.json）*
*Cloud 模型：gpt-oss-120b*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.05 | CER≤0.10 | CER>0.10 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.2707 | 0/4 | 0 | 0 | 4 | 2.6s | 0.154x |

> Cloud API 用量：input 1421 tokens, output 1119 tokens, total 2540 tokens

## 2. 逐条对比（含文本）

### cs_error_01 (code_switching)

**期望**: 这个error是null pointer exception。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.379** | 这个 error 是 no pointer it se。 |

### ascend_cs_003 (real_ascend_codeswitching)

**期望**: 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.353** | 深圳或者是上海，这种表达城市会有更 opportun。 |

### wenet_net_001 (real_wenetspeech)

**期望**: 毕业歌会之后，然后我们还去吃个饭，然后就感觉。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.217** | 毕业歌会之后，我们去吃饭，然后就感。 |

### cs_edge_008 (real_codeswitching)

**期望**: CI pipeline跑了30分钟，还没通过unit test。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.133** | CI pipeline 跑了 30 分钟，还没通过 unit。 |

## 3. Cloud vs Local 差异分析

---

*报告由 `scripts/benchmark_cloud_rewrite.py` 自动生成*