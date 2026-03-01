# 并发架构与状态管理重构方案

*2026-03-01 — Concurrency Architecture & State Management Round Table*

---

## 1. 专家组成员

| 角色 | 关注点 |
|------|--------|
| **Modern Swift Concurrency Expert (The Modernizer)** | GCD 滥用、回调地狱、`actor` / `async/await` 迁移 |
| **State Machine Architect (The Simplifier)** | 布尔标志散乱、控制流复杂度、FSM 建模 |
| **macOS CoreAudio Expert (The HAL Guardian)** | 实时音频线程安全、`installTap` 回调不可阻塞 |

---

## 2. Phase 1: Code Smell 审计

### 2.1 当前队列拓扑 (Queue-Hopping Map)

代码中存在 **4 个不同的执行上下文**，且数据在它们之间频繁跳转：

```
┌──────────────────┐     ┌─────────────────────┐
│  CoreAudio HAL   │     │   Main Thread        │
│  (real-time)     │     │   (UI + state)       │
│                  │     │                       │
│  installTap      │     │  KeyMonitor callback  │
│  callback        │     │  startRecording()     │
│  ──────────────▶ │     │  stopRecording()      │
│  processAudio()  │     │  onPartialResult      │
│                  │     │  onAudioLevel          │
└────────┬─────────┘     └──────────┬────────────┘
         │                          │
         │  DispatchQueue           │
         │  .main.async             │
         ▼                          ▼
┌──────────────────┐     ┌─────────────────────┐
│  recognitionQueue│     │   stateQueue         │
│  (serial, .user  │     │   (serial)           │
│   Initiated)     │     │                       │
│                  │     │  _isRecording         │
│  acceptWaveform  │     │  _isInitializing      │
│  decode          │     │  _accumulatedText     │
│  flush           │     │                       │
│  reset           │     │                       │
└──────────────────┘     └─────────────────────┘
         │                          ▲
         │  stateQueue.sync         │
         └──────────────────────────┘
```

### 2.2 已识别的并发缺陷

#### 缺陷 #1: [CRITICAL] flush/reset 竞态条件

**文件**: `RecordingManager.swift:254-263` vs `ASREngine.swift:131-151`

**场景**: 用户快速释放 Fn → 按下 Fn

```
时间线:
t0  stopRecording()    → isRecording = false
t1                     → engine.flush { ... }  ← recognitionQueue.async (排队)
t2  startRecording()   → accumulatedText = ""
t3                     → recognitionQueue.sync { reset() }  ← 等待 recognitionQueue
t4                     → (recognitionQueue 开始执行 flush)
t5                     → flush 内部调用 reset()
t6                     → (recognitionQueue 执行来自 t3 的 sync block — 但 flush 已在先)
t7                     → 新音频开始流入

BUG: t3 的 recognitionQueue.sync 确实会等 flush 完成，但 flush 内部的
     reset()（ASREngine.swift:146）和 startRecording 中的 reset() 导致
     stream 被销毁/重建两次。虽然功能上不致命，但存在冗余。

更严重的是: 在 t0-t2 期间，isRecording 已经为 false，但 flush callback
还没返回。如果 flush callback 中访问 self.accumulatedText（line 369），
它可能读到 t2 已清空的值而非 flush 真正要的值。
```

**修复前 Bug #1 的情况更严重**：旧代码没有 `recognitionQueue.sync`，所以 reset 可以在 flush 执行之前或同时运行，导致状态泄露。

#### 缺陷 #2: [HIGH] `accumulatedText` 语义冲突

**文件**: `RecordingManager.swift:20,258,338,365,369`

`accumulatedText` 有两个写入者：

| 写入者 | 线程 | 时机 |
|--------|------|------|
| `processAudioBuffer` | CoreAudio → recognitionQueue → callback | 持续写入部分结果 |
| `startRecording` | Main Thread | 重置为 "" |

以及两个读取者：

| 读取者 | 线程 | 时机 |
|--------|------|------|
| `processAudioBuffer` → `onPartialResult` | Main Thread (via async) | 实时更新 UI |
| `stopRecording` → flush callback | Main Thread (via async) | 获取 fallback 文本 |

虽然 `stateQueue.sync` 保护了单个读写操作，但**读写之间的复合操作不是原子的**。例如：

```swift
// stopRecording 中（line 365-369）：
let text = rawText.isEmpty ? self.accumulatedText : rawText
```

这里的 `accumulatedText` 读取与 `rawText.isEmpty` 判断之间，另一个 `processAudioBuffer` callback 可能已经修改了 `accumulatedText`（虽然概率极低，因为此时音频引擎已停止，但存在窗口期）。

#### 缺陷 #3: [MEDIUM] Boolean Flag Soup — 状态不可枚举

**文件**: `RecordingManager.swift:18-20`

当前有 3 个独立布尔标志：

| 标志 | 含义 |
|------|------|
| `_isRecording` | 是否正在录音 |
| `_isInitializing` | 是否正在初始化模型 |
| `_accumulatedText` | 累积的识别文本（实为状态的一部分） |

这导致 $2^3 = 8$ 种可能的状态组合，但很多是非法的：

| isRecording | isInitializing | accumulatedText | 合法? |
|-------------|----------------|-----------------|-------|
| false | false | "" | ✅ idle |
| false | true | "" | ✅ 正在初始化 |
| true | false | "xxx" | ✅ 正在录音 |
| true | true | "xxx" | ❌ 非法：初始化时不应录音 |
| false | false | "xxx" | ⚠️ 已停止但文本未清理 |

没有编译期或运行时约束来阻止非法状态组合。

#### 缺陷 #4: [MEDIUM] `onPartialResult` / `onAudioLevel` 回调裸暴露

**文件**: `RecordingManager.swift:53-55` 和 `TypelessApp.swift:122-131,145-146`

```swift
// Main thread (TypelessApp.swift:122-131)
RecordingManager.shared.onPartialResult = { ... }
RecordingManager.shared.onAudioLevel = { ... }

// CoreAudio callback → recognitionQueue → callback:
self.onPartialResult?(text)  // line 340

// Main thread (TypelessApp.swift:145-146)
RecordingManager.shared.onPartialResult = nil
RecordingManager.shared.onAudioLevel = nil
```

`onPartialResult` 和 `onAudioLevel` 是**非线程安全的可变回调属性**。它们从 Main Thread 设置/清除，但从 CoreAudio callback chain 中读取和调用。虽然 Swift 中闭包赋值本身是原子的，但**设置回调和开始录音之间没有 happens-before 保证**。

#### 缺陷 #5: [MEDIUM] `processAudioBuffer` 在 CoreAudio 线程上做重活

**文件**: `RecordingManager.swift:299-342`

`installTap` 的回调运行在 CoreAudio 的**实时优先级线程**上。当前代码在该回调中做了：

1. `AVAudioConverter.convert()` — 合理，轻量操作
2. `Array(UnsafeBufferPointer(...))` — **堆分配**，在 RT 线程上不理想
3. RMS 计算循环 — 合理
4. `DispatchQueue.main.async` — **可能阻塞**如果 main queue 拥塞
5. `currentEngine?.processAudio(samples: ...)` — 在 FunASR 引擎中，这直接调用 `vad.acceptWaveform()` 后跟 `recognitionQueue.async`；在 Streaming Paraformer 中，直接 `recognitionQueue.async`

**CoreAudio HAL Guardian 判定**：第 2 项（堆分配）和第 4 项（main queue async）理论上违反了 RT 线程的"无内存分配、无锁"约束。但实践中：

- macOS 的 `installTap` 回调实际运行在 `com.apple.coreaudio.ioqueue` 上，**不是**硬实时 HAL I/O thread。它是 Apple 提供的中间层，容忍轻量的内存分配。
- 真正的 HAL I/O thread（`IOProc`）是此回调的上游，`installTap` 提供了缓冲保护。
- 因此，当前代码在 `installTap` 回调中的操作是**可接受的**，不会导致音频断裂。

但如果未来如需降低延迟（如从 4096 帧降到 512 帧），这些操作可能成为瓶颈。

#### 缺陷 #6: [LOW] GCD + async/await 混用

**文件**: `RecordingManager.swift:65,402` 和 `SettingsView.swift:95`

```swift
// RecordingManager.swift:65
Task { await initializeRecognizer() }

// 但 initializeRecognizer 内部又混用 GCD：
private func initializeRecognizer() async {
    guard !isInitializing else { return }  // stateQueue.sync
    isInitializing = true                   // stateQueue.sync
    ...
}
```

`Task { }` 创建的是非结构化任务，继承当前 actor 上下文（这里是 Main Actor，因为 `init()` 在 main thread 调用）。但 `initializeRecognizer()` 不是 `@MainActor` 也不在 actor 上，所以 Swift 并发运行时可能在任意线程上执行它。这与 `isInitializing` 的 GCD `stateQueue.sync` 保护产生了**两套并发控制机制的叠加**，增加了认知复杂度。

### 2.3 缺陷汇总

| ID | 严重度 | 类型 | 描述 |
|----|--------|------|------|
| #1 | CRITICAL | 竞态条件 | flush/reset 交错导致状态泄露 |
| #2 | HIGH | 语义冲突 | accumulatedText 多写者/多读者复合操作非原子 |
| #3 | MEDIUM | 状态膨胀 | 布尔标志组合爆炸，非法状态无约束 |
| #4 | MEDIUM | 线程安全 | 回调属性裸暴露，无同步保护 |
| #5 | MEDIUM | RT 线程 | CoreAudio 回调中有堆分配（当前可容忍） |
| #6 | LOW | 架构混乱 | GCD 与 async/await 双轨并行 |

---

## 3. Phase 2: 重构方案辩论

### 3.1 Option A: Actor 模型 + async/await (The Modernizer 提案)

#### 设计

```swift
@globalActor actor RecordingActor {
    static let shared = RecordingActor()
}

@RecordingActor
class RecordingManager {
    private var state: RecordingState = .idle
    private var currentEngine: (any ASREngine)?
    private var accumulatedText: String = ""
    // ... 不再需要 stateQueue、recognitionQueue
}
```

#### 优点

- **数据隔离保证**：actor 内的所有属性自动互斥，消除手动队列管理
- **消除回调地狱**：`flush()` 可以变成 `async func flush() -> String`
- **编译期检查**：跨 actor 访问必须 `await`，编译器会报错

#### 缺点

- **CoreAudio 兼容性问题**：`installTap` 回调是 C 风格同步回调，不能直接 `await` actor 方法。需要一个桥接层（如 `AsyncStream`）将音频数据从 CoreAudio 回调传递到 actor 上下文
- **迁移成本高**：所有调用者（`TypelessApp`、`SettingsView`、`ASREngine` 实现）都需要适配 `await`
- **潜在性能问题**：actor 的 serial executor 等同于 serial queue。如果 CSC/punctuation 的 ONNX 推理（~30ms）在 actor 上执行，会阻塞 actor 的其他操作（包括接收新音频）
- **最低部署目标**：需要 macOS 12+（已满足）

#### HAL Guardian 审查

> `installTap` 回调在 CoreAudio 的 IOQueue 上运行，**不能 await**。必须引入 `AsyncStream<[Float]>` 作为桥接：
>
> ```swift
> let (stream, continuation) = AsyncStream<[Float]>.makeStream()
>
> inputNode.installTap(...) { buffer, time in
>     // RT 线程：只做最轻量的操作
>     let samples = extractSamples(buffer)
>     continuation.yield(samples)  // lock-free enqueue
> }
>
> // Actor 上消费
> Task { @RecordingActor in
>     for await samples in stream {
>         engine.processAudio(samples)
>     }
> }
> ```
>
> `AsyncStream.Continuation.yield()` 内部使用 lock-free buffer，对 RT 线程安全。但 `extractSamples()` 中的 `Array(UnsafeBufferPointer(...))` 仍然有堆分配。建议使用预分配的环形缓冲区。

### 3.2 Option B: 状态机 + 单队列 (The Simplifier 提案)

#### 设计

```swift
enum RecordingState {
    case idle
    case initializing
    case ready                  // 模型已加载，等待录音
    case recording(accumulatedText: String)
    case flushing(accumulatedText: String)
    case postProcessing(rawText: String)
}

class RecordingManager {
    /// 所有状态变更必须且只能通过此队列
    private let stateQueue = DispatchQueue(label: "com.typeless.state")
    private var state: RecordingState = .idle

    /// 事件驱动的状态转换
    private func transition(_ event: RecordingEvent) {
        stateQueue.async {
            let oldState = self.state
            guard let newState = Self.nextState(from: oldState, event: event) else {
                logger.warning("非法转换: \(oldState) + \(event)")
                return
            }
            self.state = newState
            self.handleSideEffects(from: oldState, to: newState, event: event)
        }
    }
}
```

#### 状态转换图

```
                    ┌─── loadModel() ──┐
                    │                   ▼
              ┌──── idle ◄───── initializing
              │       ▲
              │       │ modelLoaded()
              │       │
              │     ready ◄─────────────────────────┐
              │       │                              │
              │       │ fnKeyDown                    │ textInserted
              │       ▼                              │
              │   recording ─── fnKeyUp ──▶ flushing ┤
              │       │                      │       │
              │       │                      │       │
              │       │ partial              │ flushComplete
              │       │ result               ▼       │
              │       └──┐           postProcessing──┘
              │          │            (CSC + punct)
              │          │
              │          └─▶ recording (accText updated)
              │
              └── (error) ──▶ idle
```

#### 关键规则

1. **所有转换在 `stateQueue` 上串行执行** — 消除竞态
2. **状态枚举携带关联值** — `accumulatedText` 嵌入状态，消除独立变量
3. `recognitionQueue` 保留，仅用于 compute-heavy 的 ASR decode — 不持有任何状态
4. 副作用（启动/停止音频、调用 CSC/标点）由 `handleSideEffects` 统一触发

#### 优点

- **最小改动**：保留 GCD 架构，不引入新的并发范式
- **状态可枚举**：编译器保证 `switch` 穷尽所有状态，非法转换被显式拒绝
- **调试友好**：每次转换可打日志，完整重放状态历史
- **CoreAudio 零影响**：`installTap` 回调逻辑不变，只是最终通过 `transition(.audioReceived(samples))` 发事件
- **不阻塞 RT 线程**：事件通过 `stateQueue.async` 异步发送

#### 缺点

- **不是编译期安全**：仍需手动确保状态转换正确（靠单元测试覆盖）
- **`stateQueue.async` 增加一跳**：所有来自 CoreAudio 的音频都要先经过 stateQueue，再转发到 recognitionQueue。但 stateQueue 上的操作只有状态检查（纳秒级），不构成瓶颈
- **没有解决回调嵌套**：`flush` 仍然需要 completion handler（除非在 FSM 中改用事件驱动）

#### HAL Guardian 审查

> Option B 对 CoreAudio 回调的影响最小。`installTap` 回调中只需增加一行 `self.transition(.audioReceived(samples))`，其中 `transition` 使用 `stateQueue.async`（异步，不阻塞 RT 线程）。
>
> `stateQueue` 上的处理应严格限制为状态检查 + 转发到 `recognitionQueue`，确保耗时 < 1μs。

### 3.3 专家组辩论与决策

| 维度 | Option A (Actor) | Option B (FSM) |
|------|------------------|----------------|
| **线程安全** | 编译期保证 | 运行时保证（单队列串行） |
| **改动量** | 大（全局重构） | 中（主要改 RecordingManager + ASREngine） |
| **CoreAudio 兼容** | 需要 AsyncStream 桥接 | 零改动 |
| **性能风险** | actor executor 可能被 ONNX 推理阻塞 | stateQueue 仅做调度，不会阻塞 |
| **回调消除** | 完全消除 | 可改为事件驱动，消除大部分 |
| **可测试性** | 需要 actor isolation 测试工具 | 可直接测试状态转换表 |
| **团队学习曲线** | 高（actor, Sendable, isolation） | 低（FSM 是经典模式） |

#### 决策：推荐 Option B (FSM) 并借鉴 Option A 中的 async/await 思想

**理由**：

1. **CoreAudio 约束是硬性的**。Actor 模型要求在 actor 边界上 `await`，但 CoreAudio 回调不支持 `await`。AsyncStream 桥接虽然可行，但引入了额外的复杂度和一个缓冲层。对于一个低延迟语音助手，每一毫秒都重要。

2. **ONNX 推理的阻塞问题**。CSC 推理 ~30ms，标点推理 ~15ms，如果在 actor 上执行，会阻塞 actor 的 serial executor 45ms，期间无法接收新音频。解决方案是把推理放到 detached task，但这又绕过了 actor isolation 的保护。

3. **改动量和风险**。Option B 可以**增量迁移**：先替换 RecordingManager 中的布尔标志为 enum，再逐步清理回调。Option A 是全盘重写。

4. **选择性引入 async/await**：对于 `initializeRecognizer()`、`loadVAD()`、`loadITNFst()` 等模型加载路径，保留现有的 `async/await`，这是合适的。只有热路径（音频处理 + 识别）用 FSM + GCD。

---

## 4. Phase 3: 重构实施计划

### 4.1 新架构概览

```
┌─────────────────────────────────────────────────┐
│                  TypelessApp                     │
│  onKeyDown → manager.handleEvent(.fnKeyDown)    │
│  onKeyUp   → manager.handleEvent(.fnKeyUp)      │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│              RecordingManager (FSM)              │
│                                                  │
│  ┌──────────────────────────────┐               │
│  │  stateQueue (serial)         │               │
│  │  ┌────────────────────────┐  │               │
│  │  │  state: RecordingState │  │               │
│  │  │                        │  │               │
│  │  │  .idle                 │  │               │
│  │  │  .ready                │  │               │
│  │  │  .recording(text)      │  │               │
│  │  │  .flushing             │  │               │
│  │  │  .postProcessing(text) │  │               │
│  │  └────────────────────────┘  │               │
│  │                              │               │
│  │  transition(event) {         │               │
│  │    validate → update state   │               │
│  │    → trigger side effects    │               │
│  │  }                           │               │
│  └──────────────────────────────┘               │
│                                                  │
│  ┌──────────────────────────────┐               │
│  │  recognitionQueue (serial)   │  ← compute    │
│  │  ASR decode, flush           │     only       │
│  └──────────────────────────────┘               │
│                                                  │
│  ┌──────────────────────────────┐               │
│  │  CoreAudio installTap        │  ← RT-safe     │
│  │  → stateQueue.async {        │               │
│  │      transition(.audio(...)) │               │
│  │    }                         │               │
│  └──────────────────────────────┘               │
└─────────────────────────────────────────────────┘
```

### 4.2 类型定义

```swift
/// 录音管理器的有限状态
enum RecordingState: CustomStringConvertible {
    case idle                          // 无引擎或引擎未就绪
    case initializing                  // 正在加载模型
    case ready                         // 等待 Fn 按下
    case recording(accumulatedText: String)  // 录音中
    case flushing                      // 正在刷出最终结果
    case postProcessing(rawText: String)     // CSC + 标点处理

    var description: String {
        switch self {
        case .idle: return "idle"
        case .initializing: return "initializing"
        case .ready: return "ready"
        case .recording: return "recording"
        case .flushing: return "flushing"
        case .postProcessing: return "postProcessing"
        }
    }
}

/// 驱动状态转换的事件
enum RecordingEvent {
    case modelLoaded
    case modelLoadFailed
    case fnKeyDown
    case fnKeyUp
    case audioReceived(samples: [Float])
    case partialResult(text: String)
    case flushComplete(rawText: String)
    case postProcessComplete(finalText: String?)
    case reloadRequested
}
```

### 4.3 状态转换表

| 当前状态 | 事件 | 下一状态 | 副作用 |
|---------|------|---------|--------|
| idle | modelLoaded | ready | — |
| idle | reloadRequested | initializing | 启动模型加载 |
| initializing | modelLoaded | ready | — |
| initializing | modelLoadFailed | idle | log error |
| ready | fnKeyDown | recording("") | 启动 AVAudioEngine, 安装 tap |
| ready | reloadRequested | initializing | 清理引擎，启动模型加载 |
| recording(t) | audioReceived(s) | recording(t) | 转发到 recognitionQueue |
| recording(t) | partialResult(t') | recording(t') | 通知 UI |
| recording(t) | fnKeyUp | flushing | 停止音频, 调用 engine.flush |
| flushing | flushComplete(raw) | postProcessing(raw) | 启动 CSC + 标点 |
| postProcessing(t) | postProcessComplete(final) | ready | 输出文本, 清理 |
| **任意状态** | fnKeyDown（非 ready） | **忽略** | log warning |
| **任意状态** | fnKeyUp（非 recording） | **忽略** | log warning |

### 4.4 分步实施指南

#### Step 1: 定义状态枚举和事件枚举

**新增文件**: `Sources/RecordingState.swift`

定义 `RecordingState` 和 `RecordingEvent` 枚举。独立文件便于单元测试。

#### Step 2: 重构 RecordingManager 核心

**修改文件**: `Sources/RecordingManager.swift`

变更：
- 删除 `_isRecording`、`_isInitializing`、`_accumulatedText` 三个布尔/字符串标志
- 新增 `private var state: RecordingState = .idle`
- 新增 `func handleEvent(_ event: RecordingEvent)` 作为唯一公开入口
- 将 `startRecording()` / `stopRecording()` 改为 private，由 `handleEvent` 内部调用
- `stateQueue` 保留，所有 `state` 读写和转换判断在此队列上

公开 API 变更：

```swift
// 旧 API
func startRecording()
func stopRecording(completion: @escaping (String?) -> Void)

// 新 API
func handleEvent(_ event: RecordingEvent)
var onFinalResult: ((String?) -> Void)?  // 替代 completion callback
```

#### Step 3: 适配 TypelessApp

**修改文件**: `Sources/TypelessApp.swift`

```swift
// 旧代码
keyMonitor?.onKeyDown = { [weak self] in self?.startRecording() }
keyMonitor?.onKeyUp = { [weak self] in self?.stopRecordingAndTranscribe() }

// 新代码
keyMonitor?.onKeyDown = {
    RecordingManager.shared.handleEvent(.fnKeyDown)
}
keyMonitor?.onKeyUp = {
    RecordingManager.shared.handleEvent(.fnKeyUp)
}

// 最终结果通过 onFinalResult 回调接收
RecordingManager.shared.onFinalResult = { [weak self] text in
    ...
}
```

#### Step 4: 适配 ASREngine

**修改文件**: `Sources/ASREngine.swift`

`processAudio` 和 `flush` 的回调改为通过事件驱动：

```swift
// 旧
func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void)
func flush(completion: @escaping (String) -> Void)

// 新 — 回调改为注入的事件发送器
func processAudio(samples: [Float], eventSink: @escaping (RecordingEvent) -> Void)
func flush(eventSink: @escaping (RecordingEvent) -> Void)
```

Engine 内部在产生结果时调用 `eventSink(.partialResult(text))` 或 `eventSink(.flushComplete(rawText))`，由 RecordingManager 的 FSM 接收并处理。

#### Step 5: 保持 CoreAudio 回调不变

`installTap` 回调逻辑保持不变。唯一变化是回调末尾的 `currentEngine?.processAudio(...)` 改为通过 FSM 事件分发：

```swift
inputNode.installTap(...) { [weak self] buffer, time in
    let samples = self?.extractSamples(buffer, converter, targetFormat)
    if let samples = samples {
        self?.handleEvent(.audioReceived(samples: samples))
    }
}
```

`handleEvent` 在 `stateQueue.async` 上执行，不阻塞 CoreAudio 回调线程。

#### Step 6: 单元测试

**新增文件**: `Tests/RecordingStateTests.swift`

测试纯状态转换逻辑：

```swift
func testNormalFlow() {
    var state: RecordingState = .ready
    state = RecordingState.transition(from: state, event: .fnKeyDown)
    XCTAssertEqual(state, .recording(accumulatedText: ""))

    state = RecordingState.transition(from: state, event: .fnKeyUp)
    XCTAssertEqual(state, .flushing)
}

func testIgnoreInvalidEvents() {
    let state: RecordingState = .idle
    let next = RecordingState.transition(from: state, event: .fnKeyDown)
    XCTAssertEqual(next, .idle)  // 忽略，因为没有引擎
}
```

### 4.5 回归风险控制

| 风险 | 缓解措施 |
|------|---------|
| 重构后录音不工作 | Step 2 和 Step 3 合并为单次提交，每步都可编译通过 |
| 状态机遗漏转换 | 用 `switch` 穷尽匹配，编译器报错 |
| CoreAudio 延迟增加 | 插入 signpost 测量 `handleEvent(.audioReceived)` 到 `processAudio` 的延迟 |
| ASREngine 接口变更 | Step 4 可独立进行，先兼容旧/新两套接口 |

### 4.6 不在此次重构范围内

- `SherpaOnnxManager` 的下载逻辑（已稳定，无并发问题）
- `KeyMonitor` 的 CGEventTap 逻辑（单线程，无并发问题）
- `ChineseSpellingCorrector` 和 `BertTokenizer`（无状态或只读，线程安全）
- `SettingsView` / `ModelDownloadManager`（UI 层，main thread only）

---

## 5. 总结

| 问题 | 解决 |
|------|------|
| 布尔标志散乱，状态不可枚举 | `RecordingState` enum 作为 Single Source of Truth |
| flush/reset 竞态 | 所有状态转换在 `stateQueue` 上串行执行 |
| accumulatedText 多写者冲突 | 嵌入为 `recording(accumulatedText:)` 的关联值 |
| 回调裸暴露 | 用事件驱动替代直接回调赋值 |
| CoreAudio RT 安全 | `installTap` 回调保持不变，仅 `stateQueue.async` 发事件 |
| GCD + async/await 混用 | 热路径用 FSM + GCD，冷路径（模型加载）保留 async/await |

---

## 附录: 技术术语表

> 本节为非专业读者提供文档中出现的技术术语解释。如果你已经熟悉这些概念，可以跳过。

### 并发与线程相关

| 术语 | 英文 | 解释 |
|------|------|------|
| **线程 (Thread)** | Thread | 程序中的一条独立执行路径。就像一家餐厅的一位厨师——一个厨师一次只能做一道菜，多个厨师可以同时做不同的菜。程序中的多条线程可以同时执行不同的任务。 |
| **并发 (Concurrency)** | Concurrency | 多个任务在时间上重叠执行。不一定是真正的"同时"，可能是快速切换（就像一个厨师在两道菜之间来回切换），也可能是真正的并行（多个厨师同时做菜）。 |
| **GCD** | Grand Central Dispatch | 苹果提供的并发编程框架。它帮你管理线程，你只需要把任务提交到"队列"里，系统自动安排在合适的线程上执行。名字来源于纽约的 Grand Central Terminal（中央车站）——所有任务在这里被调度和分发。 |
| **队列 (Queue)** | Dispatch Queue | GCD 的核心概念。一个任务排队的通道。有两种：**串行队列**（任务排队一个一个执行，像单车道）和**并行队列**（多个任务可以同时执行，像多车道高速公路）。 |
| **串行队列 (Serial Queue)** | Serial Queue | 一次只执行一个任务的队列。就像银行的单窗口排队——前一个人办完，下一个人才能办。这保证了任务之间不会互相干扰。文档中的 `stateQueue` 和 `recognitionQueue` 都是串行队列。 |
| **Main Thread / 主线程** | Main Thread | 程序中负责更新用户界面（UI）的特殊线程。所有按钮点击、文字显示等 UI 操作必须在主线程上执行。如果主线程被耗时任务阻塞，界面就会"卡住"。 |
| **异步 (async)** | Asynchronous | "我把任务交给你，你慢慢做，我先去干别的事"。调用者不等任务完成就继续往下执行。与之相对的是**同步 (sync)**——"我等你做完才继续"。 |
| **`async/await`** | async/await | Swift 5.5 引入的现代异步编程语法。`async` 标记一个函数"可能需要等待"，`await` 表示"在这里等一下结果"。比 GCD 的回调嵌套更容易阅读。 |
| **Actor** | Actor | Swift 并发模型中的一种类型，自动保证内部数据一次只有一个任务在访问。就像一个带锁的房间——每次只允许一个人进去操作里面的东西，其他人必须在门口排队等待。 |

### 竞态与安全

| 术语 | 英文 | 解释 |
|------|------|------|
| **竞态条件 (Race Condition)** | Race Condition | 两个或多个线程同时读写共享数据，结果取决于谁先执行，导致不可预测的 bug。就像两个人同时编辑同一份 Google 文档的同一行——最终结果取决于谁最后保存，可能丢失一方的修改。 |
| **线程安全 (Thread Safety)** | Thread Safety | 代码在多线程环境下也能正确工作的保证。如果一个函数是线程安全的，多个线程可以同时调用它而不会出错。 |
| **死锁 (Deadlock)** | Deadlock | 两个线程互相等待对方释放资源，导致永远卡住。就像两辆车在窄路上迎面相遇，都等对方先让路，结果谁也走不了。 |
| **原子操作 (Atomic Operation)** | Atomic Operation | 不可被中断的操作——要么完整执行，要么完全不执行，不会出现"做了一半"的状态。就像银行转账：扣款和入账必须同时完成，不能只完成一半。 |

### 状态管理

| 术语 | 英文 | 解释 |
|------|------|------|
| **FSM / 有限状态机** | Finite State Machine | 一种建模方式：系统在任何时刻只能处于有限个"状态"中的一个，并且通过明确定义的"事件"从一个状态转换到另一个状态。就像交通信号灯——只有红、黄、绿三个状态，按固定规则切换。 |
| **状态转换 (State Transition)** | State Transition | 从一个状态变到另一个状态的过程。例如：从"等待录音"变为"正在录音"是一次状态转换，由"用户按下 Fn 键"这个事件触发。 |
| **布尔标志 (Boolean Flag)** | Boolean Flag | 一个只有 true 或 false 的变量，用来表示某种状态。单独用还好，但当系统用多个布尔标志组合表示状态时（如 `isRecording`、`isInitializing`），容易出现非法组合（如录音和初始化同时为 true）。这就是文档中说的"布尔标志汤 (Boolean Flag Soup)"。 |
| **枚举 (Enum)** | Enumeration | Swift 中的一种类型，定义一组命名的可能值。比如 `RecordingState` 枚举只能是 `.idle`、`.ready`、`.recording` 等几个值之一，编译器会确保你处理了所有可能的值。用枚举替代多个布尔标志可以在编译期阻止非法状态。 |
| **关联值 (Associated Value)** | Associated Value | Swift 枚举的特性——每个枚举值可以携带额外数据。例如 `.recording(accumulatedText: "你好")` 不仅表示"正在录音"状态，还携带了当前识别的文本。 |
| **回调 (Callback)** | Callback | 一个传给别人的函数，"等你做完了，调用这个函数通知我"。例如 `stopRecording(completion:)` 中的 `completion` 就是回调——录音停止后，系统通过这个回调把最终文本交还给调用者。 |
| **回调地狱 (Callback Hell)** | Callback Hell | 回调嵌套过深导致代码难以阅读和维护。当操作 A 的回调里启动操作 B，B 的回调里启动操作 C，代码会不断缩进，像一个向右倾斜的金字塔。 |

### 音频相关

| 术语 | 英文 | 解释 |
|------|------|------|
| **CoreAudio** | CoreAudio | macOS/iOS 底层音频框架，负责与声卡硬件交互。它处理麦克风输入、扬声器输出等底层操作。 |
| **HAL** | Hardware Abstraction Layer | 硬件抽象层。CoreAudio 中负责直接与音频硬件通信的部分。HAL 层的代码运行在"实时线程"上，对响应时间要求极高。 |
| **实时线程 (RT Thread)** | Real-Time Thread | 对时间极其敏感的线程。音频硬件每隔固定时间（如每 5ms）需要一批音频数据。如果实时线程没有及时提供数据，就会出现"音频断裂"（听到卡顿或爆音）。因此实时线程上禁止做任何耗时操作：不能申请内存、不能等锁、不能做磁盘读写。 |
| **`installTap`** | installTap | AVAudioEngine 的一个方法，在音频管线上"装一个水龙头"，截取流过的音频数据。每当有新的音频数据流过，系统会调用你提供的回调函数，把数据交给你处理。 |
| **采样率 (Sample Rate)** | Sample Rate | 每秒采集音频样本的次数。16000 Hz（= 16 kHz）意味着每秒采集 16000 个数据点。采样率越高，音频质量越好。语音识别通常使用 16 kHz。 |
| **VAD** | Voice Activity Detection | 语音活动检测——判断当前音频中是否有人在说话。用于区分"说话"和"静音"，帮助识别器知道一句话什么时候开始、什么时候结束。 |

### ASR / 语音识别相关

| 术语 | 英文 | 解释 |
|------|------|------|
| **ASR** | Automatic Speech Recognition | 自动语音识别——把语音转换为文字的技术。手机上的"语音输入"就是 ASR。 |
| **流式识别 (Streaming Recognition)** | Streaming Recognition | 边录音边识别，实时显示部分结果。用户还没说完，屏幕上就已经开始显示文字了。与之相对的是"离线识别"——等录音全部结束后才开始转换。 |
| **flush** | Flush | "冲刷"——在录音结束时，把识别器内部缓冲的最后一批音频数据强制处理完毕，得到最终识别结果。就像邮局关门前把最后一批信件全部投递出去。 |
| **ITN** | Inverse Text Normalization | 逆文本正规化——把口语化的数字/单位表达转换为书面形式。例如："一万两千三百四十五" → "12345"，"百分之九十" → "90%"。 |
| **CSC** | Chinese Spelling Correction | 中文拼写纠错——检测和纠正同音字/近音字错误。例如 ASR 把"心情"误识别为"新情"，CSC 可以纠正过来。 |
| **ONNX Runtime** | ONNX Runtime | 微软开源的 AI 推理引擎。可以在本地（不联网）运行预训练的 AI 模型。本项目用它在 Mac 上本地运行语音识别、标点恢复和拼写纠错模型。 |
| **WFST / FST** | (Weighted) Finite State Transducer | 加权有限状态转换器——一种高效的字符串转换工具，常用于 ITN。可以把它想象成一个智能的"查找替换"工具，按照预定义的规则将输入文本转换为输出文本。 |

### GCD 滥用 (GCD Abuse) 详解

文档中提到的"GCD 滥用"指的是以下几种不良模式：

1. **队列跳跃 (Queue Hopping)**：数据在多个队列之间频繁跳转。例如：CoreAudio 线程 → `recognitionQueue` → `stateQueue` → 主线程。每一次跳转都增加了复杂度和出错的可能性。

2. **双轨并行**：代码中同时使用 GCD（`DispatchQueue.async`/`.sync`）和 Swift `async/await` 两套并发机制来管理状态。这导致开发者需要同时理解两套模型的交互，增加了认知负担和 bug 风险。

3. **散弹式锁保护**：用 `stateQueue.sync { }` 逐个保护每个属性的读写，但不保护操作之间的逻辑一致性。就像用挂锁锁每个抽屉，但没有锁房间门——虽然每个抽屉单独是安全的，但打开多个抽屉的组合操作可能出问题。

正确的做法是**选择一种并发模型**（GCD 或 async/await），并用**状态机**统一管理所有状态变更，而非用多个队列保护散落的变量。
