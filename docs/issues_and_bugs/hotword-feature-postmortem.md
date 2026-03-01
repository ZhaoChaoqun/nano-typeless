# Streaming Paraformer 热词（Hotword）功能 — 设计、实现与回滚记录

## 1. 背景与目标

Nano Typeless 使用 sherpa-onnx 的 Streaming Paraformer 作为主要 ASR 引擎。为了提升技术词汇（如 Kubernetes、Docker、async 等）的识别准确率，我们计划利用 sherpa-onnx 的 **Contextual Biasing（上下文偏置/热词）** 功能，让识别器在解码时偏向预设词汇。

### 功能预期

- 内置 43 个开发者常用术语作为默认热词
- 用户可在设置界面自定义热词和热词加分值
- 热词在 stream 级别注入，无需重载模型

---

## 2. 技术调研

### 2.1 sherpa-onnx C API 中的热词接口

在 `c-api.h` 中找到以下相关定义：

```c
// SherpaOnnxOnlineRecognizerConfig 中的字段
const char *hotwords_file;    // 热词文件路径
float hotwords_score;         // 热词加分值（默认 1.5）
const char *hotwords_buf;     // 内存中的热词字符串（换行分隔）
int32_t hotwords_buf_size;    // 热词字符串大小

// Stream 创建 API
SHERPA_ONNX_API const SherpaOnnxOnlineStream *
SherpaOnnxCreateOnlineStreamWithHotwords(
    const SherpaOnnxOnlineRecognizer *recognizer,
    const char *hotwords);
```

### 2.2 调研结论（当时）

- `SherpaOnnxCreateOnlineStreamWithHotwords` 可以在创建 stream 时注入热词
- 热词以换行 (`\n`) 分隔的字符串形式传入
- `hotwords_score` 控制偏置强度，默认 1.5
- `SherpaOnnxOnlineStreamReset` 只清除模型/解码状态，不影响热词设置
- 热词是 per-stream 的，更改热词只需重建 stream，不需要重载 recognizer

### 2.3 调研遗漏（根本原因）

**sherpa-onnx 的 Contextual Biasing/热词功能仅支持 Transducer 架构模型。** Streaming Paraformer 不是 Transducer 模型，因此不支持热词偏置。

C 头文件中虽然定义了热词相关的字段和函数，但 **运行时** sherpa-onnx 会检查模型类型。对非 Transducer 模型调用 `SherpaOnnxCreateOnlineStreamWithHotwords` 会触发致命错误：

```
Only transducer models support contextual biasing.
```

支持热词的模型示例：
- Zipformer-Transducer（如 `sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20`）
- 其他基于 RNN-T / Transducer 解码器的模型

**不支持** 热词的模型：
- Paraformer（包括 Streaming Paraformer）
- SenseVoice / FunASR Nano
- Qwen-ASR

---

## 3. 实现方案（已回滚）

### 3.1 架构设计

```
┌──────────────────┐     ┌───────────────────────┐
│  SettingsView     │────▶│  HotwordManager       │
│  (热词 UI Section) │     │  (内置 + 用户自定义)   │
└──────────────────┘     └───────────┬───────────┘
                                     │
                                     ▼
                          ┌───────────────────────┐
                          │  RecordingManager      │
                          │  (传入热词到 recognizer) │
                          └───────────┬───────────┘
                                     │
                                     ▼
                    ┌──────────────────────────────────┐
                    │  SherpaOnnxOnlineRecognizer       │
                    │  (FFI 调用 C API 热词接口)         │
                    └──────────────────────────────────┘
```

### 3.2 修改的文件

#### Phase 1: FFI 层 — `SherpaOnnxOnlineRecognizer.swift`

- `init` 新增 `hotwords: String?` 和 `hotwordsScore: Float` 参数
- 设置 `config.hotwords_score`
- 有热词时调用 `SherpaOnnxCreateOnlineStreamWithHotwords`，无热词时调用 `SherpaOnnxCreateOnlineStream`
- 新增 `recreateStream(hotwords:)` 方法用于动态更换热词
- 新增 `makeStream(recognizer:hotwords:cStrings:)` 静态方法封装 stream 创建逻辑

#### Phase 2: 数据层 — `HotwordManager.swift`（新建）

```swift
class HotwordManager: ObservableObject {
    static let shared = HotwordManager()

    @Published var userHotwords: String   // UserDefaults 持久化
    @Published var hotwordsScore: Float   // UserDefaults 持久化，默认 1.5

    static let builtinHotwords: [String]  // 43 个内置开发者术语
    var combinedHotwords: String { get }  // 内置 + 用户自定义，换行分隔
}
```

内置热词包括：
- 编程语言：Swift、Rust、Python、JavaScript、TypeScript、Kotlin、Java、Golang
- 开发工具：Xcode、VS Code、Docker、Kubernetes、Git、GitHub、GitLab
- 关键字：struct、class、enum、protocol、impl、async、await、func、var、let、import
- Git 操作：commit、push、pull、merge、rebase、checkout、branch、stash
- 常见术语：API、SDK、CLI、UI、JSON、YAML、HTTP、HTTPS、WebSocket、npm、pip、cargo、brew

#### Phase 3: 集成层 — `RecordingManager.swift`

- `initializeStreamingParaformer()` 中从 `HotwordManager.shared` 获取合并热词和分数
- 传给 `SherpaOnnxOnlineRecognizer` 的初始化方法

#### Phase 4: UI 层 — `SettingsView.swift`

- 新增 `@StateObject private var hotwordManager = HotwordManager.shared`
- 当选中 Streaming Paraformer 时显示"热词设置" Section：
  - 热词加分值 Slider（0.5 ~ 10.0）
  - 自定义热词 TextEditor（每行一个）
  - Footer 提示内置热词数量
- 窗口高度从 520 调整为 620

#### Xcode 项目文件 — `project.pbxproj`

- 新增 `HotwordManager.swift` 的 PBXBuildFile 和 PBXFileReference 条目

---

## 4. 运行时错误

构建 Release 版本后运行，切换到 Streaming Paraformer 时（因为热词功能只在 Streaming Paraformer 下启用），控制台输出致命错误：

```
Only transducer models support contextual biasing.
```

程序崩溃/识别器创建失败。

### 错误根因

sherpa-onnx 的热词（Contextual Biasing）功能在 **编译层面** 对所有模型类型暴露了统一的 C API，但在 **运行时** 会检查模型架构。只有 Transducer 模型内部实现了 WFST 热词集成的逻辑，其他架构（CTC、Paraformer 等）不支持。

C 头文件中的字段和函数声明 **不代表** 所有模型都支持这些功能。这是一个典型的"API 可用性 ≠ 功能可用性"的陷阱。

---

## 5. 回滚操作

### 回滚的文件

| 文件 | 操作 |
|------|------|
| `Sources/SherpaOnnxOnlineRecognizer.swift` | 恢复到仅接受 `encoderPath`、`decoderPath`、`tokensPath`、`ruleFstsPath` 参数的原始版本；移除 `hotwords`、`hotwordsScore`、`makeStream`、`recreateStream` |
| `Sources/RecordingManager.swift` | 移除所有 `HotwordManager` 引用，恢复直接调用 `SherpaOnnxOnlineRecognizer(encoderPath:decoderPath:tokensPath:ruleFstsPath:)` |
| `Sources/SettingsView.swift` | 移除热词 Section UI 代码、移除 `hotwordManager` StateObject、窗口高度恢复为 520 |
| `Sources/HotwordManager.swift` | 删除整个文件 |
| `Typeless.xcodeproj/project.pbxproj` | 移除 `1AFF0001` 和 `1AFF0010` 共 4 行条目 |

### 保留的变更

- **ITN (Inverse Text Normalization)** 功能不受影响 — `ruleFstsPath` 参数和 `itn_zh_number.fst` 支持仍然保留并正常工作

---

## 6. 后续可选方案

如果未来需要热词支持，有以下可选路径：

### 方案 A：切换到 Transducer 模型

使用支持热词的 Zipformer-Transducer 双语模型（如 `sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20`），原生支持 Contextual Biasing。

**优点**：原生支持，无需额外开发
**缺点**：需要评估 Transducer 模型的识别质量和性能是否达到 Paraformer 水平

### 方案 B：文本后处理替换

在识别结果上做后处理，用正则/字典匹配替换常见错误（如"库伯奈特斯" → "Kubernetes"）。

**优点**：不依赖模型特性，适用于所有引擎
**缺点**：治标不治本，维护成本高，可能引入误替换

### 方案 C：等待 Paraformer 热词支持

关注 sherpa-onnx 项目更新，如果未来 Paraformer 架构增加 Contextual Biasing 支持再启用。

---

## 7. 经验教训

1. **API 存在 ≠ 功能可用**：C 头文件中声明了函数和字段，不代表所有模型类型都实现了对应功能。需要查看具体模型的文档或源码确认兼容性。

2. **尽早做运行时验证**：对于涉及外部 C 库的功能，应该在编写完整 UI 和集成代码之前，先写一个最小原型验证核心 API 调用是否成功。

3. **Transducer vs 非 Transducer**：sherpa-onnx 支持多种模型架构（Transducer、CTC、Paraformer），但某些高级功能（如热词偏置）只在特定架构上可用。选型时需要综合考虑功能需求。

---

*文档创建时间：2026-02-27*
*项目：Nano Typeless*
*涉及版本：热词功能从实现到回滚的完整生命周期*
