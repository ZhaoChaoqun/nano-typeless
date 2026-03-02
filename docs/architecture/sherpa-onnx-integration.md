# Sherpa-ONNX 集成文档

本文档介绍 Typeless 应用中 Sherpa-ONNX 语音识别框架的集成。

## 概述

Typeless 使用 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 作为 Streaming Paraformer 和 FunASR Nano LLM 两个引擎的推理后端。sherpa-onnx 是 k2-fsa 开源的离线语音识别框架，支持多种模型架构。

## 当前支持的引擎

| 引擎 | 后端 | 说明 |
|------|------|------|
| Streaming Paraformer | sherpa-onnx (Online API) | 流式中英文识别 |
| FunASR Nano LLM | sherpa-onnx (通过自定义 C 桥接) | SenseVoice encoder + Qwen3-0.6B LLM 离线识别 |
| Qwen3-ASR | Rust FFI (libqwen_asr) | 独立引擎，不依赖 sherpa-onnx |

## 集成架构

```
┌─────────────────────────────────────────────────────────────┐
│                    RecordingManager (FSM)                     │
│  ┌──────────────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ StreamingParaformer-  │  │ FunASRNano-  │  │ QwenASR-   │ │
│  │ Engine               │  │ LLMEngine    │  │ Engine     │ │
│  └──────────┬───────────┘  └──────┬───────┘  └──────┬─────┘ │
│             │                      │                  │       │
│             ▼                      ▼                  ▼       │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐ │
│  │ SherpaOnnxOnline │  │ FunASRNanoLLM    │  │ libqwen_   │ │
│  │ Recognizer       │  │ Recognizer       │  │ asr (Rust) │ │
│  └──────────┬───────┘  └──────┬───────────┘  └────────────┘ │
│             │                  │                              │
│             ▼                  ▼                              │
│  ┌─────────────────────────────────────┐                     │
│  │  CSherpaOnnx (C API 桥接)           │                     │
│  └──────────────────┬──────────────────┘                     │
│                     ▼                                        │
│  ┌─────────────────────────────────────┐                     │
│  │  Sherpa-ONNX 动态库 (.dylib)        │                     │
│  │  + ONNX Runtime                    │                     │
│  └─────────────────────────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

## 关键文件

### Swift 封装

| 文件 | 说明 |
|------|------|
| `Sources/SherpaOnnxOnlineRecognizer.swift` | Streaming Paraformer 在线识别器封装 |
| `Sources/FunASRNanoLLMRecognizer.swift` | FunASR Nano LLM 识别器封装 |
| `Sources/SherpaOnnxManager.swift` | 模型下载和路径管理 |
| `Sources/SherpaOnnxVAD.swift` | Silero VAD 语音活动检测封装 |
| `Sources/SherpaOnnxPunctuation.swift` | CT-Transformer 标点模型封装 |

### C 桥接

| 文件 | 说明 |
|------|------|
| `Sources/CSherpaOnnx/module.modulemap` | Swift 模块映射 |
| `Sources/CSherpaOnnx/shim.h` | 头文件包装 |
| `Sources/CSherpaOnnx/sherpa-onnx/c-api/c-api.h` | Sherpa-ONNX C API 头文件 |

### 动态库

| 文件 | 说明 |
|------|------|
| `Frameworks/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib` | Sherpa-ONNX C API 库 |
| `Frameworks/sherpa-onnx/lib/libonnxruntime.1.17.1.dylib` | ONNX Runtime 库 |

## 构建注意事项

### dylib 签名

sherpa-onnx 的 dylib 文件 Team ID 与主程序不匹配，Release 构建后需要使用 ad-hoc 签名重新签名：

```bash
cd "build/Build/Products/Release/Nano Typeless.app/Contents/Frameworks"
codesign --force --sign - libsherpa-onnx-c-api.dylib libonnxruntime.1.17.1.dylib
codesign --force --sign - "../../Nano Typeless.app"
```
