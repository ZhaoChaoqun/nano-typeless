# Typeless ASR 处理流水线架构

*文档版本：2026-03-01*

---

## 1. 整体架构概览

Typeless 支持三个 ASR 引擎，每个引擎的后处理链不同：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Typeless ASR Pipeline                        │
│                                                                     │
│  麦克风 → 音频采集 (16kHz mono f32) → AVAudioEngine                  │
│                          │                                          │
│              ┌───────────┼───────────┐                              │
│              ▼           ▼           ▼                              │
│     ┌──────────────┐ ┌────────┐ ┌──────────┐                       │
│     │ FunASR Nano  │ │Streaming│ │ Qwen3-ASR│                       │
│     │ LLM          │ │Parafor- │ │          │                       │
│     │              │ │mer      │ │          │                       │
│     │ VAD 分段     │ │         │ │          │                       │
│     │ + LLM 识别   │ │ 流式识别│ │ 流式识别 │                       │
│     │              │ │         │ │          │                       │
│     │ ITN: 内置    │ │ITN: FST │ │ ITN: 内置│                       │
│     │ 标点: 内置   │ │         │ │ 标点: 内置│                       │
│     └──────┬───────┘ └────┬────┘ │ 纠错: 内置│                       │
│            │              │      └─────┬────┘                       │
│            │              │            │                             │
│            │              ▼            │                             │
│            │       ┌──────────────────────────┐                     │
│            │       │ CSC 中文拼写纠错          │                     │
│            │       │ (macbert4csc INT8, 98MB) │                     │
│            │       │ ~15-30ms                 │                     │
│            │       └────────────┬─────────────┘                     │
│            │                    ▼                                    │
│            │       ┌──────────────────────────┐                     │
│            │       │ CT-Transformer 标点模型   │                     │
│            │       │ (62MB)                   │                     │
│            │       └────────────┬─────────────┘                     │
│            │                    │                                    │
│            ▼                    ▼                     ▼              │
│              最终文本 ──────────────> 粘贴到光标位置                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 三个引擎的处理流水线

### 2.1 Streaming Paraformer

```
音频输入 (16kHz f32)
    │
    ▼
┌─────────────────────────────────┐
│  SherpaOnnxOnlineRecognizer     │
│                                 │
│  acceptWaveform(samples)        │
│       │                         │
│       ▼                         │
│  decode() ← 流式解码             │
│       │                         │
│       ▼                         │
│  ITN (itn_zh_number.fst)        │  ← 在解码过程中自动应用
│  中文数字 → 阿拉伯数字            │     通过 config.rule_fsts 配置
│  "一百二十三" → "123"            │
│       │                         │
│       ▼                         │
│  getResult() → 原始文本          │
└────────────┬────────────────────┘
             │
             ▼  flush() 后
┌─────────────────────────────────┐
│  CSC 纠错 (macbert4csc)         │
│                                 │
│  "今天新情很好" → "今天心情很好"   │
│                                 │
│  • BERT 逐字分词                 │
│  • ONNX Runtime 前向传播         │
│  • argmax + logit 差值 > 2.0    │
│  • 仅纠正中文字符                │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│  标点处理 (CT-Transformer)      │
│                                 │
│  "今天心情很好" → "今天心情很好。" │
│                                 │
│  SherpaOfflinePunctuationAddPunct()
└────────────┬────────────────────┘
             │
             ▼
          最终文本
```

**关键文件：**
- ITN 加载：`RecordingManager.swift:131` → `loadITNFst()`
- ITN 配置：`SherpaOnnxOnlineRecognizer.swift:57` → `config.rule_fsts`
- CSC 调用：`RecordingManager.swift:374`
- 标点调用：`RecordingManager.swift:375`

---

### 2.2 FunASR Nano LLM

```
音频输入 (16kHz f32)
    │
    ▼
┌─────────────────────────────────┐
│  Silero VAD                     │
│                                 │
│  acceptWaveform(samples)        │
│       │                         │
│       ▼                         │
│  语音活动检测 → 分段              │
│  静音段切分为多个 SpeechSegment   │
└────────────┬────────────────────┘
             │ 每个语音段
             ▼
┌─────────────────────────────────┐
│  FunASRNanoLLMRecognizer        │
│  (SenseVoice encoder + Qwen3   │
│   0.6B LLM)                    │
│                                 │
│  transcribe(segment.samples)    │
│       │                         │
│       ▼                         │
│  LLM 自动完成：                  │
│    ✅ ITN（数字转换）             │
│    ✅ 标点（自动添加）            │
│       │                         │
│       ▼                         │
│  累积文本                        │
└────────────┬────────────────────┘
             │
             ▼
          最终文本  ← 无外部后处理
```

**与 Streaming Paraformer 的区别：**
- 需要 VAD 做语音分段（Paraformer 不需要）
- 使用 SenseVoice encoder + Qwen3 LLM 进行离线识别
- LLM 内部自带标点和 ITN，不需要外部 CSC/标点后处理

---

### 2.3 Qwen3-ASR

```
音频输入 (16kHz f32)
    │
    ▼
┌─────────────────────────────────┐
│  QwenASRStreamRecognizer        │
│                                 │
│  pushAudio(samples)             │
│       │                         │
│       ▼                         │
│  Qwen3 大模型解码                │
│  ┌───────────────────────────┐  │
│  │ 自动完成全部后处理：        │  │
│  │  ✅ ITN（数字转换）        │  │
│  │  ✅ 标点（自动添加）       │  │
│  │  ✅ 拼写纠错              │  │
│  └───────────────────────────┘  │
│       │                         │
│       ▼                         │
│  getResult() → 完整文本          │
│  （已含标点、已纠错）             │
└────────────┬────────────────────┘
             │
             ▼  flush() 后
          最终文本  ← 无任何外部后处理
```

**关键：** `needsPunctuation = false`，跳过 CSC 和标点处理。

---

## 3. 后处理模块调用顺序

```
              FunASR Nano LLM          Streaming Paraformer         Qwen3-ASR
              ─────────────           ──────────────────          ─────────
                   │                         │                        │
                   │                  ┌───────┴───────┐               │
                   │                  │ ITN (FST 文件) │               │
                   │                  │ rule_fsts     │               │
                   │                  └───────┬───────┘               │
              全部在 LLM                       │                  全部在模型
              内部完成                          ▼                  内部完成
                   │          ┌────────────────────────────────┐      │
                   │          │         CSC 中文拼写纠错         │      │
                   │          │         (macbert4csc-base)      │      │
                   │          └───────────────┬────────────────┘      │
                   │                          │                       │
                   │                          ▼                       │
                   │          ┌────────────────────────────────┐      │
                   │          │         CT-Transformer 标点模型  │      │
                   │          └───────────────┬────────────────┘      │
                   │                          │                       │
                   ▼                          ▼                       ▼
               最终文本                    最终文本                 最终文本
```

---

## 4. 模型文件清单

| 模块 | 模型文件 | 大小 | 存储路径 |
|------|---------|------|---------|
| Streaming Paraformer | encoder.int8.onnx, decoder.int8.onnx, tokens.txt | ~216MB | `models/sherpa-onnx-streaming-paraformer-bilingual-zh-en/` |
| Qwen3-ASR | Qwen3-ASR-0.6B 模型文件 | ~1.2GB | `models/Qwen3-ASR-0.6B/` |
| FunASR Nano LLM | encoder_adaptor, llm, embedding, tokenizer | ~716MB | `models/funasr-nano-llm/` |
| VAD | silero_vad.onnx | ~2MB | `models/silero_vad.onnx` |
| ITN | itn_zh_number.fst | ~200KB | `models/itn_zh_number.fst` |
| CSC 纠错 | model_int8.onnx, vocab.txt | ~98MB | `models/macbert4csc-base-chinese/` |
| 标点 | model.int8.onnx | ~62MB | `models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8/` |

所有模型存储在 `~/Library/Application Support/Nano Typeless/models/` 下。

---

## 5. 各引擎后处理模块依赖

| 后处理模块 | Streaming Paraformer | FunASR Nano LLM | Qwen3-ASR |
|-----------|:-:|:-:|:-:|
| VAD (silero_vad) | ❌ | ✅ 必需 | ❌ |
| ITN (itn_zh_number.fst) | ✅ 必需 | ❌ 内置 | ❌ 内置 |
| CSC (macbert4csc) | ✅ 可选 | ❌ 不需要 | ❌ 不需要 |
| 标点 (CT-Transformer) | ✅ 必需 | ❌ 内置 | ❌ 内置 |
| `needsPunctuation` | `true` | `false` | `false` |

---

## 6. 关键代码入口

| 功能 | 文件 | 位置 |
|------|------|------|
| 引擎选择与初始化 | `RecordingManager.swift` | `initializeRecognizer()` |
| Paraformer ITN 配置 | `SherpaOnnxOnlineRecognizer.swift:57` | `config.rule_fsts` |
| 后处理链（CSC→标点） | `RecordingManager.swift` | `performPostProcessing()` |
| CSC 推理 | `ChineseSpellingCorrector.swift` | `correctSpelling()` |
| 标点推理 | `SherpaOnnxPunctuation.swift` | `addPunctuation()` |
| 后处理开关 | `ASREngine.swift:21` | `needsPunctuation` |
