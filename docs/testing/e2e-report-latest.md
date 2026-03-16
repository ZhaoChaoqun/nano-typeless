# ASR 测试报告: E2E

*生成时间: 2026-03-13T08:29:57Z*  |  *Commit: d0a9d27 (main)*
*对比基准: 2026-03-13T08:26:59Z (unknown)*

---

# Qwen3-ASR (offline)

## 1. 总览

| 指标 | 当前 | 上次 | 变化 |
|------|:----:|:----:|:----:|
| 总条目 | 43 | 43 | - |
| 通过 | 35 (81.4%) | 35 (81.4%) | +0 |
| 失败 | 8 (18.6%) | 8 (18.6%) | +0 |
| 平均 CER | 0.136 | 0.136 | - |
| 中位 CER | 0.000 | 0.000 | - |
| RTF | 0.113x | 0.112x | +0.001 ↑ |

## 2. 改善的 Case (CER ↓)

*无改善的条目。*

## 3. 退化的 Case (CER ↑)

*无退化的条目。*

## 4. 失败 Case 明细

共 8 条失败：

| # | ID | 类别 | CER | 期望文本 | 实际输出 |
|---|-----|------|:---:|---------|---------|
| 1 | hal_silence_30s | hallucination | 1.000 |  | 嗯。 |
| 2 | hal_breath_01 | hallucination | 1.000 |  | 嗯。 |
| 3 | hal_white_noise_01 | hallucination | 1.000 |  | 嗯。 |
| 4 | silence_02 | silence_short | 1.000 |  | 嗯。 |
| 5 | silence_01 | silence | 1.000 |  | 嗯。 |
| 6 | cs_edge_003 | code_switching | 0.293 | 用 Docker Compose 部署了 3 个 microservice... | 用 Docker Compose 部署了三个 微服务 到 staging 环境。 |
| 7 | cs_review_01 | code_switching | 0.130 | 帮我review一下这个pull request。 | 帮我review一下这个po request。 |
| 8 | cs_edge_008 | code_switching | 0.107 | CI pipeline 跑了 30 分钟，还没通过 unit test。 | CI pipeline跑了30min，还没通过unit test。 |

## 5. 按类别 CER 汇总

| 类别 | 条数 | 平均 CER | CER=0 | CER≤0.10 | CER>0.10 |
|------|:----:|:-------:|:-----:|:--------:|:--------:|
| chinese_long | 1 | 0.000 | 1 | 1 | 0 |
| chinese_short | 1 | 0.000 | 1 | 1 | 0 |
| code_switching | 13 | 0.052 | 8 | 10 | 3 |
| developer_corpus | 8 | 0.017 | 6 | 8 | 0 |
| english_short | 1 | 0.000 | 1 | 1 | 0 |
| hallucination | 4 | 0.750 | 1 | 1 | 3 |
| long_audio | 2 | 0.002 | 1 | 2 | 0 |
| mid_sentence_pause | 2 | 0.000 | 2 | 2 | 0 |
| mixed_technical | 1 | 0.045 | 0 | 1 | 0 |
| mixed_zh_en | 1 | 0.000 | 1 | 1 | 0 |
| punctuation | 3 | 0.000 | 3 | 3 | 0 |
| silence | 1 | 1.000 | 0 | 0 | 1 |
| silence_short | 1 | 1.000 | 0 | 0 | 1 |
| speech_rate | 2 | 0.000 | 2 | 2 | 0 |
| speech_trailing_silence | 1 | 0.000 | 1 | 1 | 0 |
| technical_numbers | 1 | 0.000 | 1 | 1 | 0 |

---
