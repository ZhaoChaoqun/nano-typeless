# Typeless 项目文档索引

本目录包含 Typeless 项目的所有技术文档，按类别组织在子目录中。

---

## 目录结构

```
docs/
├── architecture/       # 系统架构、集成设计、架构决策记录
├── research/           # 模型调研、技术评估、方案对比
├── guides/             # 算法教程、参数配置、技术原理
├── issues_and_bugs/    # Bug 根因分析、Post-Mortem、问题修复记录
└── testing/            # 测试覆盖、测试计划、质量保障
```

---

## architecture/ — 系统设计与架构决策

系统级设计文档、集成方案论证、架构审计报告。

| 文档 | 说明 |
|------|------|
| [asr-pipeline-architecture.md](architecture/asr-pipeline-architecture.md) | Typeless 三引擎 ASR 处理流水线架构（Paraformer / FunASR Nano LLM / Qwen3-ASR）|
| [sherpa-onnx-integration.md](architecture/sherpa-onnx-integration.md) | Sherpa-ONNX 集成架构（Paraformer + FunASR Nano LLM 引擎接入）|
| [qwen3-asr-integration-comparison.md](architecture/qwen3-asr-integration-comparison.md) | Qwen3-ASR 接入方案对比：Rust FFI vs 嵌入 Python mlx-audio |
| [qwen3-asr-optimization-report.md](architecture/qwen3-asr-optimization-report.md) | Qwen3-ASR Rust FFI 性能优化报告（调用链路、瓶颈分析）|
| [full-repo-audit-report.md](architecture/full-repo-audit-report.md) | 全仓库架构与用户体验审计报告（5 专家交叉审查）|

## research/ — 调研与技术评估

ASR 模型选型、数据集调研、技术方案评估、对比分析。

| 文档 | 说明 |
|------|------|
| [asr-landscape-report-2026.md](research/asr-landscape-report-2026.md) | ASR 前沿技术全景调研 2025/2026（中文 & 中英混合场景）|
| [asr-models-survey-2025.md](research/asr-models-survey-2025.md) | 主流 ASR 模型调研报告（15+ 开源模型 + 商业 API）|
| [asr-datasets-survey.md](research/asr-datasets-survey.md) | ASR 语音数据集调研（AISHELL / MINDS-14 / ASCEND / WenetSpeech 等）|
| [qwen3-asr-quantization-report.md](research/qwen3-asr-quantization-report.md) | Qwen3-ASR 模型量化版本调研（w4a16 / INT8 体积与性能对比）|
| [qwen3-asr-vs-paraformer-analysis.md](research/qwen3-asr-vs-paraformer-analysis.md) | Qwen3-ASR vs Streaming Paraformer 准确度深入对比分析 |
| [itn-wfst-research-report.md](research/itn-wfst-research-report.md) | 中文 ITN WFST 方案调研（WeTextProcessing vs FunTextProcessing）|
| [csc-correction-guide.md](research/csc-correction-guide.md) | CSC（中文拼写纠错）技术调研与 Typeless 集成方案 |

## guides/ — 技术指南与教程

算法原理讲解、配置参数详解、技术概念教程。

| 文档 | 说明 |
|------|------|
| [bpe-algorithm-guide.md](guides/bpe-algorithm-guide.md) | BPE (Byte Pair Encoding) 算法深入浅出（含 GPT-2 Byte-Level BPE）|
| [streaming-params-guide.md](guides/streaming-params-guide.md) | Qwen3-ASR 流式识别四大配置参数详解（chunk_sec / rollback / unfixed_chunks / max_new_tokens）|
| [nar-streaming-guide.md](guides/nar-streaming-guide.md) | NAR 模型 Streaming 方案详解（Paraformer 流式改造原理）|

## issues_and_bugs/ — Bug 分析与 Post-Mortem

Bug 根因分析报告、功能回滚复盘、问题修复记录。

| 文档 | 说明 |
|------|------|
| [debug-utf8-report.md](issues_and_bugs/debug-utf8-report.md) | UTF-8 字符乱码根因分析（英文版）— GPT-2 BPE 解码 Bug |
| [debug-utf8-report-cn.md](issues_and_bugs/debug-utf8-report-cn.md) | UTF-8 字符乱码根因分析（中文版）— 同上 |
| [csc-bug-analysis.md](issues_and_bugs/csc-bug-analysis.md) | CSC 中文拼写纠错 Bug 分析（vocabSize 计算错误导致全乱码）|
| [itn-fst-bug-analysis.md](issues_and_bugs/itn-fst-bug-analysis.md) | ITN FST "一些→1些" Bug 分析与修复（FST 无上下文感知）|
| [hotword-feature-postmortem.md](issues_and_bugs/hotword-feature-postmortem.md) | Streaming Paraformer 热词功能 Post-Mortem（设计、实现与回滚）|

## testing/ — 测试与质量保障

测试覆盖文档、测试计划、E2E 测试用例清单。

| 文档 | 说明 |
|------|------|
| [test-coverage-expansion.md](testing/test-coverage-expansion.md) | Qwen3-ASR 测试覆盖文档（109 个测试，5 个测试类）|

---

## 如何添加新文档

1. 根据文档类型选择对应子目录
2. 使用 `kebab-case` 命名（如 `my-new-report.md`）
3. 如果现有目录不适合，可以创建新的子目录
4. 更新本索引文件，添加新文档的链接和说明
