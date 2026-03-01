# Nano Typeless — 全仓库架构与用户体验审计报告

**审计日期**: 2026-02-25
**审计范围**: 全部 Swift 源码 (13 文件, ~3,000 行)、Rust FFI 层、构建脚本、UI 交互
**审计方法**: 专家委员会圆桌模拟（5 位虚拟专家逐文件交叉审查）

---

## 目录

1. [执行摘要](#1-执行摘要)
2. [UX 与交互审计](#2-ux-与交互审计)
3. [架构与代码质量](#3-架构与代码质量)
4. [Qwen3-ASR 集成评估](#4-qwen3-asr-集成评估)
5. [战略路线图](#5-战略路线图)

---

## 1. 执行摘要

### 整体健康度: B+ (良好，有明确改进空间)

| 维度 | 评分 | 说明 |
|------|------|------|
| **架构** | B | 关注点分离清晰，但 RecordingManager 职责过重 |
| **性能** | B+ | 音频管线高效，Qwen3-ASR 流式设计合理 |
| **稳定性** | B- | 线程安全存在风险点，缺乏错误恢复机制 |
| **可扩展性** | B | 三引擎切换设计良好，但 Protocol 抽象缺失 |
| **可读性** | A- | 代码简洁自文档，中文注释友好 |
| **用户体验** | B | Push-to-talk 交互简洁，但状态反馈可感知性不足 |

### 核心优势
- **极简设计**：~3,000 行 Swift 实现完整的本地语音输入，没有过度工程
- **多引擎架构**：FunASR Nano / Streaming Paraformer / Qwen3-ASR 三引擎并存
- **全本地处理**：无网络依赖的隐私优先架构
- **Qwen3 流式集成**：通过 Rust FFI + 累积缓冲策略，在非原生流式模型上实现了流式体验

### 关键风险
- `RecordingManager` 中存在跨线程可变状态竞争
- `toCString()` 存在系统性内存泄漏
- Qwen3-ASR 的 `audio_buf` 累积缓冲区无上限增长
- 缺乏单元测试和自动化 CI

---

## 2. UX 与交互审计

> **审计专家**: Senior Product Designer (IXD/UX)

### 2.1 状态可视化评估

#### 当前实现

| 应用状态 | 视觉反馈 | 评估 |
|----------|----------|------|
| **Idle（空闲）** | 菜单栏静态 `waveform` 图标 | 合理，不打扰用户 |
| **Listening（录音中）** | 悬浮窗 + 7 条声波竖纹动画 + "正在聆听..." | 有反馈，但**不区分有声/无声** |
| **Processing（识别中）** | 无独立处理状态——松开 Fn 后窗口直接消失 | **严重缺失**：用户感知为"什么都没发生" |
| **Result（输出）** | 文字通过 Cmd+V 粘贴到光标位置 | 功能可用，但缺少成功确认 |

#### 关键 UX 问题

**问题 1: 松开 Fn 后缺乏过渡状态**

```
当前流程: [松开 Fn] → overlay 立即 hide() → 后台识别 → 粘贴
用户感知: "窗口消失了，我不知道它有没有在工作"
```

`TypelessApp.swift:124-137` 中，`stopRecordingAndTranscribe()` 在回调返回前就通过 `overlayWindow?.hide()` 隐藏了窗口。对于离线模型 (FunASR) 和 QwenASR finalize，这意味着存在用户可感知的空白等待期。

**建议**: 在 `hide()` 前显示一个短暂的 "处理中" / spinning 状态，finalize 完成后再隐藏。

**问题 2: 声波动画不响应真实音频**

`OverlayWindow.swift:204-209` 中的声波动画是纯数学函数 `sin(phase)`，与实际麦克风输入无关：

```swift
private func waveHeight(for index: Int) -> CGFloat {
    let phase = viewModel.animationPhase + CGFloat(index) * 0.6
    let baseHeight: CGFloat = 6
    let amplitude: CGFloat = 10
    return baseHeight + abs(sin(phase)) * amplitude
}
```

用户说话时和保持沉默时，动画完全相同。这打破了 "系统在倾听我" 的心理模型。

**建议**: 将 `processAudioBuffer` 中的 RMS 音量传给 `OverlayViewModel`，驱动声波高度。

**问题 3: VAD 切割无可视化**

FunASR Nano 模式下，VAD 将语音分段后才触发识别。在段间静默期，用户看不到任何进度变化。如果说了很长一句话但 VAD 一直没切，用户会以为系统卡住了。

### 2.2 悬浮窗体验

#### 窗口层级与行为

`OverlayWindow.swift:30-35` 的窗口配置：

```swift
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.isMovableByWindowBackground = false
```

**评价**:
- `.floating` 层级：合理，不会抢走焦点
- `.canJoinAllSpaces, .stationary`：正确，跨空间可见且不随空间切换
- 不可拖动：合理，避免意外移动

**问题**: 窗口固定在 "距屏幕顶部 60 点" 的位置 (`OverlayWindow.swift:59`)。对于使用多显示器或外接屏幕的用户，它可能:
- 被 Notch（刘海屏）遮挡
- 在非主屏幕上不可见

**建议**: 使用 `NSScreen.screens` 获取当前鼠标所在屏幕，并考虑 `safeAreaInsets` (Notch 屏)。

#### 文本溢出处理

`OverlayWindow.swift:122-124` 的设计：

```swift
private let maxWidth: CGFloat = 400
private let maxLines: Int = 5
private let lineHeight: CGFloat = 20
```

- 最大 5 行，超出后自动滚动到底部（`ScrollViewReader` + `.bottom` anchor）
- 文字宽度估算使用 `avgCharsPerLine = 25`——对中英混合文本不够精确

### 2.3 原生 macOS 体验建议

| 方面 | 当前状态 | 建议 |
|------|----------|------|
| **菜单栏状态** | 静态图标，无录音/处理状态区分 | 录音时切换为红色/脉动图标 |
| **键盘快捷键** | 仅 Fn 键 | 允许自定义修饰键组合 (如 Option+Space) |
| **声音反馈** | 无 | 录音开始/结束时可选的提示音 |
| **macOS 通知** | 无 | 模型下载完成时发送通知 |
| **Dock 状态** | `LSUIElement = true`（无 Dock 图标） | 正确，菜单栏应用应隐藏 Dock |
| **深色/浅色模式** | 浮窗固定黑底：`Color.black.opacity(0.75)` | 浮窗没问题，但 Onboarding 使用了 `NSColor.windowBackgroundColor` 自适应 |
| **Haptic 触觉反馈** | 无 | 短录音开始时的轻触反馈（MacBook/Magic Trackpad） |

### 2.4 Onboarding 体验

`OnboardingOverlay.swift` 的引导气泡设计合理：
- 首次启动自动显示在菜单栏图标下方
- 状态机清晰：`downloading` → `loading` → `ready`
- 5 秒后自动消失

**问题**: 轮询间隔 0.5 秒 (`OnboardingOverlay.swift:73`) + 可见性检查 0.5 秒 (`OnboardingOverlay.swift:175`) 使用 `Timer` 轮询而非 Combine/async 观察。功能上无碍，但不够现代。

---

## 3. 架构与代码质量

### 3.1 The Good — 做得好的地方

#### (a) 极简分层架构

```
TypelessApp (入口/生命周期)
  └─ AppDelegate
      ├─ KeyMonitor         (输入层: CGEvent Tap)
      ├─ RecordingManager   (核心: 音频+ASR编排)
      │   ├─ AVAudioEngine  (音频采集)
      │   ├─ ASR 引擎 ×3    (FunASR / Paraformer / QwenASR)
      │   ├─ VAD            (语音分段)
      │   └─ Punctuation    (标点恢复)
      ├─ OverlayWindow      (输出层: UI)
      └─ TextInserter       (输出层: 键盘模拟)
```

约 3,000 行代码实现完整功能，没有过度抽象。每个文件职责明确。

#### (b) 多引擎切换设计

`ASRModelType` 枚举 (`SherpaOnnxManager.swift:4-73`) 是一个很好的设计：
- 统一了三种引擎的元数据 (displayName, needsVAD, needsPunctuation, folderName)
- `RecordingManager.processAudioBuffer()` 通过 `switch currentModel` 分发
- `SettingsView` 通过 Picker 绑定实现无缝切换

#### (c) 智能下载源选择

`SherpaOnnxManager.selectFastestSource()` 使用 `withTaskGroup` 并行 HEAD 请求，first-win 策略：
- ModelScope（国内快）和 GitHub（海外快）双源
- 自动降级：主源失败自动尝试备用源

#### (d) FFI 封装干净

每个 C API 都有对应的 Swift 封装类，`OpaquePointer` + `deinit` 释放：
- `SherpaOnnxRecognizer` → `SherpaOnnxCreateOfflineRecognizer` / `Destroy`
- `SherpaOnnxOnlineRecognizer` → `SherpaOnnxCreateOnlineRecognizer` / `Destroy`
- `QwenASRStreamRecognizer` → `qwen_asr_load_model` / `qwen_asr_free`

#### (e) 权限处理完善

- 麦克风：`AVCaptureDevice.requestAccess` + 失败时弹窗引导
- 辅助功能：`AXIsProcessTrusted()` + 1 秒轮询等待授权 + 自动重试

### 3.2 The Bad — 技术债务

#### (a) `toCString()` 内存泄漏 — 系统性问题

以下函数出现在 4 个文件中（`SherpaOnnxRecognizer.swift:106-108`、`SherpaOnnxOnlineRecognizer.swift:154-156`、`SherpaOnnxVAD.swift:136-138`、`SherpaOnnxPunctuation.swift:58-60`）：

```swift
private func toCString(_ string: String) -> UnsafePointer<CChar>? {
    return UnsafePointer(strdup(string))
}
```

`strdup` 分配堆内存但从不 `free()`。这些字符串被传入 C 结构体的配置字段，配置使用完毕后没有释放。虽然每次初始化只泄漏几百字节，且识别器是长生命周期对象，**实际影响较小**，但这是一个不良模式。

**严重度**: 低（对长运行进程几乎无影响）
**建议**: 如果 Sherpa-ONNX API 在 Create 后会复制这些字符串，可在 Create 后 `free()`；否则保持当前做法但添加注释说明意图。

#### (b) RecordingManager 缺乏线程同步保护

`RecordingManager.swift` 中 `accumulatedText` 在多线程间共享：

- **写入 1**: `recognitionQueue.async` → `DispatchQueue.main.async { self.accumulatedText = ... }` (`RecordingManager.swift:301-304`)
- **写入 2**: `recognitionQueue.async` → `DispatchQueue.main.sync { self.accumulatedText += text }` (`RecordingManager.swift:398-399`)
- **读取**: `stopRecording()` 中在主线程读取 (`RecordingManager.swift:404`)

**风险点**: FunASR 路径中 `flushFunASR` 使用 `DispatchQueue.main.sync`（`RecordingManager.swift:398`），如果此时已经在主线程上会导致死锁。当前代码从 `recognitionQueue.async` 中调用 `.main.sync`，不会死锁。但如果未来有人从主线程调用 `flushFunASR`，将立即死锁。

此外，`isRecording`、`isInitializing` 等布尔标志没有同步保护，存在竞态条件。

#### (c) Streaming Paraformer 在音频回调线程上解码

`RecordingManager.swift:287-306` 中的 `processWithStreaming()`：

```swift
private func processWithStreaming(samples: [Float]) {
    guard let recognizer = onlineRecognizer else { return }
    recognizer.acceptWaveform(samples: samples)
    while recognizer.isReady() {
        recognizer.decode()  // 在音频回调线程上执行 CPU 密集操作！
    }
    let text = recognizer.getResult()
    // ...
}
```

`installTap` 的回调在 Core Audio 的实时线程上执行。在此线程上进行 `decode()` 操作可能导致:
- 音频缓冲区溢出（buffer overrun）
- Core Audio 检测到超时后断开 tap

对比 QwenASR 模式（`processWithQwenStreaming`）正确使用了 `recognitionQueue.async`。

**严重度**: 中高——在高实时性要求场景下可能导致卡顿或丢音频。

#### (d) Package.swift 缺少 QwenASR 链接

`Package.swift:24-28`:

```swift
linkerSettings: [
    .unsafeFlags(["-L\(packageDir)/Frameworks/sherpa-onnx/lib"]),
    .linkedLibrary("sherpa-onnx-c-api"),
    .linkedLibrary("onnxruntime")
]
```

没有链接 `libqwen_asr.dylib`。这意味着 SPM 构建路径无法使用 QwenASR 功能，只能通过 Xcode 项目构建。这不一定是问题（只要 Xcode 路径工作），但 `Package.swift` 与实际构建配置不一致。

#### (e) ModelDownloadManager 与 RecordingManager 共持 UserDefaults 状态

两个独立类同时读写 `"selectedASRModel"`：
- `RecordingManager.currentModel` getter（`RecordingManager.swift:20-24`）
- `ModelDownloadManager.switchModel()`（`SettingsView.swift:89-93`）

注释甚至承认了这个问题：

```swift
// 注意：不能用 currentModel 比较，因为 SettingsView 已经更新了 UserDefaults
```

这种隐式状态共享容易出 bug。

### 3.3 The Ugly — 关键架构缺陷

#### (a) 无错误恢复机制

整个录音-识别-插入管线没有 error propagation：

```
startRecording() → 如果 audioEngine.start() 失败 → 仅 print，UI 仍显示 "正在聆听"
stopRecording()  → 如果识别返回空 → 窗口消失，用户不知道发生了什么
insertText()     → 如果粘贴失败 → 无反馈
```

用户在使用过程中如果遇到任何异常（麦克风被其他应用占用、识别器未初始化完成就开始录音、剪贴板被锁定等），没有任何错误提示。

#### (b) TextInserter 剪贴板恢复存在竞态

`TextInserter.swift:13-30`:

```swift
let previousContents = pasteboard.string(forType: .string)
pasteboard.setString(text, forType: .string)
simulatePaste()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    if let previous = previousContents {
        pasteboard.setString(previous, forType: .string)
    }
}
```

问题：
1. 0.1 秒恢复延迟可能不够——某些应用异步处理粘贴
2. 只保存/恢复 `.string` 类型——如果用户之前复制的是图片/文件，恢复后会丢失
3. 如果用户在 0.1 秒内手动 Cmd+V，会粘贴到识别文本
4. `previousContents` 只捕获了一种 pasteboard 类型

**严重度**: 中——用户可能在不知情的情况下丢失剪贴板内容。

#### (c) RecordingManager 的 Singleton + @escaping 回调模式

```swift
RecordingManager.shared.onPartialResult = { ... }  // 设置
RecordingManager.shared.onPartialResult = nil       // 清除
```

`AppDelegate` 在 `startRecording()` 中设置回调，在 `stopRecordingAndTranscribe()` 中清除。这种手动绑定/解绑模式：
- 容易忘记清除，导致内存泄漏
- 不支持多个消费者
- 缺乏生命周期管理

### 3.4 代码卫生检查

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Magic Numbers | ⚠️ | `bufferSize: 4096`、`silencePadding count: 4800/32000`、`asyncAfter: 0.1` 等硬编码 |
| Dead Code | ✅ | `insertTextViaKeyboard` 和 `deleteCharacters` 标记为备用方案，可能未使用 |
| print 调试 | ⚠️ | 大量 `print(">>>...")` 调试输出遍布代码，应替换为 `os.Logger` |
| 重复代码 | ⚠️ | `toCString()` 在 4 个文件中重复定义 |
| 命名一致性 | ✅ | 中英文注释混合但一致，函数命名清晰 |
| 老旧兼容接口 | ⚠️ | `getModelPath()` / `isModelDownloaded()` 等旧接口仍保留 |

---

## 4. Qwen3-ASR 集成评估

> **审计专家**: Rust & Systems Performance Specialist

### 4.1 FFI 边界设计

#### C 头文件 (`qwen_asr.h`)

API 设计清晰，符合 C FFI 惯例：
- 不透明句柄模式 (`QwenAsrEngine*`, `QwenAsrStreamState*`)
- 返回堆分配字符串 + 显式 `free_string()` 释放
- 流式 API 与离线 API 分离
- 参数标注完整（PCM 格式、采样率、值域）

#### Streaming 架构

Rust 侧 (patch 文件中的 `c_api.rs`) 的流式策略：

```
Swift 侧                              Rust 侧 (QwenAsrStreamState)
┌───────────┐                          ┌────────────────────────┐
│ pushAudio │──samples──▶              │ audio_buf.extend()     │
│ (每帧)    │                          │ stream_push_audio(     │
│           │                          │   全量 audio_buf,       │
│           │◀──delta────              │   state, finalize)     │
└───────────┘                          └────────────────────────┘
```

**关键发现：累积缓冲区模式**

`qwen_asr_stream_push` 每次调用时将新采样追加到 `audio_buf`，然后将**完整的累积缓冲区**传给 `stream_push_audio`：

```rust
s.audio_buf.extend_from_slice(new_samples);
transcribe::stream_push_audio(&mut eng.ctx, &s.audio_buf, &mut s.state, finalize != 0);
```

这意味着：
- 每次调用传递的数据量线性增长
- 30 秒录音 = 16000 × 30 = 480,000 个 f32 = 1.83MB
- `stream_push_audio` 内部通过 `cursor` 跳过已处理采样，所以语义上正确

**风险**: `audio_buf` 的 `Vec<f32>` 只在 `reset()` 时清空。如果用户不松开 Fn 键持续说几分钟，内存会持续增长。对于正常使用场景（几秒到几十秒），这不是问题。

### 4.2 Swift 侧封装质量

`QwenASRRecognizer.swift` (76 行) 很简洁：

```swift
class QwenASRStreamRecognizer {
    private var engine: OpaquePointer?
    private var streamState: OpaquePointer?
    // ...
    deinit {
        if let s = streamState { qwen_asr_stream_free(s) }
        if let e = engine { qwen_asr_free(e) }
    }
}
```

**优点**:
- `deinit` 正确释放双句柄
- `pushAudio` 使用 `withUnsafeBufferPointer` 传递零拷贝指针
- `defer { qwen_asr_free_string(resultPtr) }` 正确释放返回字符串

**改进空间**:
- 没有配置流式参数的接口（`chunk_sec`、`rollback`、`max_new_tokens` 等都未暴露给 Swift）
- 线程安全依赖外部保证（`recognitionQueue`）——`engine` 和 `streamState` 可能被并发访问

### 4.3 构建管线

`build-qwen-asr.sh` 设计合理：
1. 克隆/重置 QwenASR 仓库
2. 应用 patch（crate-type + cfg 解除 + streaming FFI）
3. `cargo build --release --features ios`
4. `install_name_tool -id @rpath/...` + ad-hoc 签名
5. 验证导出符号数量

**问题**: 使用 `--features ios` 来编译 macOS dylib（因为 c_api 模块原先有 `#[cfg(feature = "ios")]` 守卫）。虽然通过 patch 移除了 cfg 限制，但 feature flag 名称具有误导性。

### 4.4 Qwen3 vs Sherpa-ONNX 对比

| 方面 | Sherpa-ONNX (FunASR/Paraformer) | Qwen3-ASR |
|------|--------------------------------|-----------|
| FFI 层 | C API (74KB 头文件, 成熟) | C API (104 行头文件, 自建) |
| 流式支持 | 原生 (Paraformer) / VAD 分段 (FunASR) | 模拟流式 (chunk + rollback) |
| 标点 | 需要外部 CT-Transformer | 自带标点 |
| 模型大小 | 179-216MB | ~1.2GB |
| 内存模式 | ONNX Runtime 管理 | Rust candle 推理框架 |
| CPU 空闲开销 | 低（仅 ONNX Runtime 常驻） | 需验证（Rust 模型常驻内存） |

---

## 5. 战略路线图

### 优先级排序

```
P0 (关键/高影响) ─────────────────────────────────────────────
│
├─ 5.1 修复 Streaming Paraformer 音频线程解码
│     将 processWithStreaming() 迁移到 recognitionQueue
│     影响: 消除音频丢失和 Core Audio 超时风险
│
├─ 5.2 添加录音结束过渡状态
│     stop 后不立即 hide()，显示 "处理中" 状态
│     影响: 大幅改善用户可感知延迟
│
P1 (重要/中影响) ─────────────────────────────────────────────
│
├─ 5.3 声波动画响应真实音量
│     将 RMS 能量传递给 OverlayViewModel
│     影响: 用户感知到 "系统在倾听我"
│
├─ 5.4 菜单栏图标状态指示
│     录音时切换为脉动红色图标
│     影响: 全局可见的录音状态
│
├─ 5.5 引入 ASR 引擎 Protocol
│     protocol ASREngine { func startStream(); func pushAudio(); ... }
│     消除 RecordingManager 中的 switch currentModel
│     影响: 降低复杂度，便于添加新引擎
│
├─ 5.6 解决 TextInserter 剪贴板问题
│     使用 NSPasteboard changeCount 检测冲突
│     保存/恢复完整 pasteboard 内容（非仅 string）
│     影响: 修复剪贴板内容丢失风险
│
P2 (改善/低影响) ─────────────────────────────────────────────
│
├─ 5.7 替换 print 为 os.Logger
│     统一日志系统，支持 Console.app 过滤
│     影响: 便于调试和用户反馈
│
├─ 5.8 统一 toCString 为全局工具函数
│     消除 4 处重复定义
│     添加注释说明内存管理策略
│
├─ 5.9 清理遗留兼容接口
│     移除 getModelPath()、isModelDownloaded() 等旧方法
│     更新 README 反映三引擎架构
│
├─ 5.10 添加核心逻辑单元测试
│      RecordingManager 的状态机
│      文本后处理（正则过滤、空格移除）
│
P3 (愿景/长期) ──────────────────────────────────────────────
│
├─ 5.11 支持自定义快捷键
│      Option+Space 或其他修饰键组合
│
├─ 5.12 多显示器 / Notch 屏适配
│      使用鼠标所在屏幕定位 overlay
│
├─ 5.13 Qwen3-ASR 流式参数调优接口
│      暴露 chunk_sec / rollback / max_new_tokens 到设置页
│
└─ 5.14 考虑 App Sandbox 兼容性
       当前关闭了 Sandbox，限制了 Mac App Store 上架
```

### 各专家的最终陈述

**Senior Product Designer**:
> 核心交互「按住-说话-松开」非常直觉，这是产品最大的优势。但松开后缺乏过渡状态会让用户产生不确定感。声波动画不响应真实声音是一个"谎言动画"——用户会注意到的。优先修复这两个问题，体验会有质的飞跃。

**System Architect**:
> 代码量控制得很好，没有过度工程。最大的结构性问题是 RecordingManager 同时承担了管线编排和状态管理两个职责，并且使用回调而非响应式模式连接 UI。引入 Protocol 抽象三个 ASR 引擎会让代码更易维护。

**Senior macOS/Swift Engineer**:
> 最紧急的问题是 Streaming Paraformer 在音频回调线程上做解码——这违反了 Core Audio 的实时线程约定。其他两个引擎已经正确使用 recognitionQueue，统一这个模式只需几行代码。另外，整个工程没有使用 Swift 的 async/await 模式管理 ASR 生命周期，现在的 Task+GCD 混合模式增加了并发推理难度。

**Rust & Systems Performance Specialist**:
> Qwen3-ASR 的 FFI 集成做得很专业——patch 策略优雅，C API 设计规范，Swift 侧零拷贝传递。累积缓冲区设计是 stream_push_audio 语义决定的，属于必要妥协。建议关注的点是：(1) 模型加载后的常驻内存消耗；(2) QwenASR finalize 时注入 2 秒静音 padding 是否可以缩短。

**Quality & Maintainability Lead**:
> 代码可读性出色——函数名清晰，注释准确，文件组织直观。主要债务是：遍布的 print 调试、4 处重复的 toCString、缺少测试。README 需要更新以反映 Qwen3-ASR 和 Streaming Paraformer 引擎。当前 README 仍然只提到 FunASR。

---

*报告结束。*
