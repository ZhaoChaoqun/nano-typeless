# Qwen3-ASR 测试策略文档

## 概述

本文档描述 Nano Typeless 项目中 Qwen3-ASR 流式识别集成的完整测试体系。

## 架构

```
┌─────────────────────┐
│   RecordingManager   │  Swift 集成层
│  processWithQwen...  │
│  flushQwenStreaming   │
└──────────┬──────────┘
           │ ASRStreamRecognizing (protocol)
┌──────────▼──────────┐
│ QwenASRStreamRecognizer │  Swift FFI 封装
│   pushAudio / getResult │
│   reset / init / deinit │
└──────────┬──────────┘
           │ C FFI (qwen_asr.h)
┌──────────▼──────────┐
│   Rust qwen-asr      │  Rust 推理引擎
│  stream_push_audio    │
│  StreamState / audio_buf
└─────────────────────┘
```

## 测试分层

### Phase 1: 测试语料 (`scripts/generate_test_corpus.py`)

生成 16kHz mono WAV 测试音频，覆盖：
- 中文短句/长句
- 中英混合
- 技术术语+数字
- 纯静音/语音+尾部静音

运行: `uv run python scripts/generate_test_corpus.py`

### Phase 2: 单元测试 (`Tests/QwenASRUnitTests.swift`)

使用 Mock 识别器测试 Swift 层逻辑，不需要模型：
- init nil 安全性
- pushAudio 参数传递
- flush 静音 padding 注入 (32000 样本)
- flush finalize 标志
- nil recognizer fallback
- accumulatedText 回退机制

### Phase 3: 边界测试 (`Tests/QwenASRBoundaryTests.swift`)

需要真实模型，无模型时自动 skip：
- **Chunk 边界**: 10ms / 1s / 一次性推入 / 变长 chunk
- **文本完整性**: getResult 单调递增、delta nil 不丢失
- **静音幻觉**: 纯静音无输出、尾部静音无幻觉
- **内存增长**: 5 分钟模拟录音 < 100MB 增长

### Phase 4: E2E 测试 (`Tests/QwenASRE2ETests.swift`)

加载真实模型 + Phase 1 语料，验证：
- 每条语料的识别质量 (CER 阈值 / 关键词匹配)
- 流式模拟 (0.5s chunk)
- 性能基准 (measure block)

## 已知风险

| 风险 | 严重度 | 覆盖测试 |
|------|--------|----------|
| audio_buf 无上限增长 | 高 | testMemoryGrowthOver5Minutes |
| CString NUL 字节截断 | 中 | testDeltaDropDoesNotLoseText |
| LLM 静音幻觉 | 中 | testPureSilenceProducesNoText |
| 跨队列 recognizer 竞态 | 中 | testRecognizerDeinitWhileQueueBusy |
| UTF-8 验证缺失 | 低 | testGetResultAlwaysReturnsFullText |

## 运行测试

```bash
# Phase 1: 生成语料
uv run python scripts/generate_test_corpus.py

# Phase 2-4: Xcode 测试（需要先添加 TypelessTests target）
xcodebuild test -project Typeless.xcodeproj -scheme TypelessTests -destination 'platform=macOS'
```
