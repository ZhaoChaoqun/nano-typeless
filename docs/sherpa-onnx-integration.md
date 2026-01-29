# Sherpa-ONNX 集成文档

本文档介绍 Typeless 应用中 Sherpa-ONNX 语音识别引擎的集成过程。

## 概述

为了支持更多的语音识别模型（Paraformer 和 SenseVoice），我们在原有 WhisperKit 的基础上集成了 Sherpa-ONNX 库。Sherpa-ONNX 是 k2-fsa 开源的离线语音识别框架，支持多种模型架构。

## 支持的模型

| 模型 | 引擎 | 特点 |
|------|------|------|
| Whisper (base/small/medium/large) | WhisperKit | OpenAI 开源模型，多语言支持 |
| Paraformer | Sherpa-ONNX | 阿里达摩院 FunASR 模型，中文优化 |
| SenseVoice Small | Sherpa-ONNX | 多语言支持，带情感识别 |

## 集成架构

```
┌─────────────────────────────────────────────────────────────┐
│                    RecordingManager                          │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │     WhisperKit      │    │    SherpaOnnxRecognizer     │ │
│  │  (Whisper 模型)     │    │  (Paraformer/SenseVoice)    │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
│                                        │                     │
│                                        ▼                     │
│                              ┌─────────────────┐            │
│                              │   CSherpaOnnx   │            │
│                              │  (C API 桥接)   │            │
│                              └─────────────────┘            │
│                                        │                     │
│                                        ▼                     │
│                              ┌─────────────────┐            │
│                              │  Sherpa-ONNX    │            │
│                              │  动态库 (.dylib) │            │
│                              └─────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

## 新增文件

### 1. Sources/SherpaOnnxRecognizer.swift

Sherpa-ONNX C API 的 Swift 封装，主要功能：

- 支持 Paraformer 和 SenseVoice 两种模型类型
- 提供 `transcribe(samples:sampleRate:)` 方法处理音频数据
- 提供 `transcribe(audioURL:)` 方法直接处理 WAV 文件
- 包含 WAV 文件解析逻辑（支持 16-bit 和 32-bit 格式）

关键代码：
```swift
class SherpaOnnxRecognizer {
    private var recognizer: OpaquePointer?
    private let modelType: ModelType

    enum ModelType {
        case paraformer
        case sensevoice
    }

    init?(modelType: ModelType, modelPath: String, tokensPath: String)
    func transcribe(samples: [Float], sampleRate: Int32 = 16000) -> String?
    func transcribe(audioURL: URL) -> String?
}
```

### 2. Sources/SherpaOnnxManager.swift

模型下载和管理器，负责：

- 检查模型是否已下载
- 下载 Paraformer 和 SenseVoice 模型
- 提供模型文件路径

### 3. Sources/CSherpaOnnx/

C 语言桥接模块，包含：

- `module.modulemap` - Swift 模块映射
- `shim.h` - 头文件包装
- `sherpa-onnx/c-api/c-api.h` - Sherpa-ONNX C API 头文件

### 4. Frameworks/sherpa-onnx/

Sherpa-ONNX 动态库：

- `lib/libsherpa-onnx-c-api.dylib` - Sherpa-ONNX C API 库
- `lib/libonnxruntime.1.17.1.dylib` - ONNX Runtime 库

## 修改的文件

### Sources/RecordingManager.swift

添加了对 Sherpa-ONNX 引擎的支持：

```swift
// 新增引擎类型枚举
enum RecognitionEngine {
    case whisper
    case paraformer
    case sensevoice
}

// 新增 Sherpa-ONNX 识别器
private var sherpaRecognizer: SherpaOnnxRecognizer?

// 根据模型 ID 选择引擎
private func getEngineType(for modelId: String) -> RecognitionEngine

// 初始化 Sherpa-ONNX
private func initializeSherpaOnnx(modelId: String) async

// 使用 Sherpa-ONNX 转录
private func transcribeWithSherpaOnnx(audioURL: URL) async -> String?
```

### Package.swift

添加了 Sherpa-ONNX 链接配置：

```swift
targets: [
    .target(
        name: "CSherpaOnnx",
        path: "Sources/CSherpaOnnx",
        publicHeadersPath: "."
    ),
    .executableTarget(
        name: "Typeless",
        dependencies: [
            "WhisperKit",
            "CSherpaOnnx"
        ],
        linkerSettings: [
            .unsafeFlags(["-L\(packageDir)/Frameworks/sherpa-onnx/lib"]),
            .linkedLibrary("sherpa-onnx-c-api"),
            .linkedLibrary("onnxruntime")
        ]
    )
]
```

## 构建说明

### Swift Package Manager 构建

```bash
cd /Users/zhaochaoqun/Github/typeless
swift build
```

### 运行（需要设置库路径）

```bash
export DYLD_LIBRARY_PATH=/Users/zhaochaoqun/Github/typeless/Frameworks/sherpa-onnx/lib:$DYLD_LIBRARY_PATH
.build/debug/Typeless
```

### Xcode 构建

Xcode 项目需要额外配置：

1. 添加 `SherpaOnnxRecognizer.swift` 和 `SherpaOnnxManager.swift` 到项目
2. 配置 Header Search Paths 包含 CSherpaOnnx 目录
3. 配置 Library Search Paths 包含 `Frameworks/sherpa-onnx/lib`
4. 添加链接库：`libsherpa-onnx-c-api.dylib` 和 `libonnxruntime.dylib`
5. 配置 Copy Files 阶段将 dylib 复制到 app bundle

## 遇到的问题及解决方案

### 1. 静态库缺少 ONNX Runtime 符号

**问题**：使用静态 xcframework 时，链接失败，报错 `_OrtGetApiBase` 未定义。

**解决**：改用 Sherpa-ONNX 共享库版本 (`sherpa-onnx-v1.12.23-onnxruntime-1.17.1-osx-universal2-shared.tar.bz2`)，包含完整的 ONNX Runtime。

### 2. C 字符串指针类型不匹配

**问题**：`strdup()` 返回 `UnsafeMutablePointer<CChar>`，但 C 结构体期望 `UnsafePointer<CChar>`。

**解决**：创建辅助函数进行类型转换：
```swift
private func toCString(_ string: String) -> UnsafePointer<CChar>? {
    return UnsafePointer(strdup(string))
}
```

### 3. 头文件路径问题

**问题**：Package 找不到 `sherpa-onnx/c-api/c-api.h`。

**解决**：将头文件复制到 `Sources/CSherpaOnnx/sherpa-onnx/c-api/c-api.h`。

### 4. 库路径配置

**问题**：相对路径 `Frameworks/sherpa-onnx/lib` 在构建时无法解析。

**解决**：使用 `Context.packageDirectory` 获取包根目录的绝对路径。

## 模型下载

模型文件存储在用户目录：

```
~/Documents/SherpaOnnx/
├── paraformer/
│   ├── model.int8.onnx
│   └── tokens.txt
└── sensevoice-small/
    ├── model.int8.onnx
    └── tokens.txt
```

模型下载 URL：
- Paraformer: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2`
- SenseVoice: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2`

## 后续工作

1. 完成 Xcode 项目配置，使其能直接从 Xcode 构建
2. 将动态库打包到 app bundle 中
3. 添加模型下载进度显示
4. 考虑支持更多 Sherpa-ONNX 模型
