# Qwen3-ASR Rust FFI 性能优化报告

> 生成日期：2026-02-27
> 项目：Nano Typeless (macOS)
> 当前引擎：Qwen3-ASR-0.6B via Rust FFI (libqwen_asr.dylib)

---

## 一、当前架构概览

### 调用链路

```
麦克风 (48kHz)
  → AVAudioEngine installTap (bufferSize: 4096)
  → AVAudioConverter 重采样 (16kHz mono float32)
  → QwenASRStreamRecognizer.pushAudio()
  → [FFI] qwen_asr_stream_push() → libqwen_asr.dylib (Rust)
  → 返回增量文本 delta
  → getResult() 获取完整累积结果
```

### 关键文件

| 文件 | 职责 |
|------|------|
| `Sources/QwenASRRecognizer.swift` | FFI 包装层，79 行 |
| `Sources/ASREngine.swift:162-207` | QwenASREngine 引擎封装 |
| `Sources/RecordingManager.swift:265` | 音频采集与 buffer 配置 |
| `Frameworks/qwen-asr/include/qwen_asr.h` | C FFI 接口定义 |
| `Frameworks/qwen-asr/lib/libqwen_asr.dylib` | Rust 编译的推理库 (689KB) |

### 当前参数配置

| 参数 | 当前值 | 代码位置 |
|------|--------|---------|
| 推理线程数 | 4 (硬编码) | `QwenASRRecognizer.swift:12` |
| 音频 tap buffer | 4096 帧 (0.256s @16kHz) | `RecordingManager.swift:265` |
| 流式 chunk 大小 | 2.0s (Rust 默认) | `qwen_asr.h:89` 未调用 |
| Token rollback | 5 (Rust 默认) | `qwen_asr.h:92` 未调用 |
| Unfixed chunks | 2 (Rust 默认) | `qwen_asr.h:95` 未调用 |
| Max new tokens/chunk | 32 (Rust 默认) | `qwen_asr.h:98` 未调用 |
| Flush 静音填充 | 2s (32000 样本) | `ASREngine.swift:192` |

### 现有亮点

- **零拷贝音频传递**：`withUnsafeBufferPointer` 直接传内存地址（`QwenASRRecognizer.swift:51`）
- **线程隔离**：推理在独立 `recognitionQueue` 上执行，不阻塞 UI
- **内存管理正确**：`defer { qwen_asr_free_string() }` 确保 Rust 分配的内存释放
- **自带标点**：`needsPunctuation = false`，无需外部标点模型

---

## 二、优化方案

### 方案 1：暴露 Rust 侧流式参数到 Swift

**难度**：低 | **收益**：中（降低出字延迟） | **需改 Rust**：否

#### 问题

`qwen_asr.h` 中定义了 4 个流式调参接口，但 Swift 侧从未调用，全部使用 Rust 默认值：

```c
// qwen_asr.h:89-98 — 已定义但未被 Swift 使用
void qwen_asr_stream_set_chunk_sec(QwenAsrEngine* engine, float sec);         // 默认 2.0
void qwen_asr_stream_set_rollback(QwenAsrEngine* engine, int32_t tokens);     // 默认 5
void qwen_asr_stream_set_unfixed_chunks(QwenAsrEngine* engine, int32_t chunks); // 默认 2
void qwen_asr_stream_set_max_new_tokens(QwenAsrEngine* engine, int32_t tokens); // 默认 32
```

#### 建议

在 `QwenASRStreamRecognizer.init()` 中，模型加载成功后调用这些配置函数：

```swift
// QwenASRRecognizer.swift init() 中，engine 创建成功后添加：
qwen_asr_stream_set_chunk_sec(engine, 1.0)        // 从 2.0 降为 1.0，减少首次出字延迟
qwen_asr_stream_set_rollback(engine, 3)            // 从 5 降为 3，减少回滚开销
qwen_asr_stream_set_unfixed_chunks(engine, 1)      // 从 2 降为 1，更快确认文本
qwen_asr_stream_set_max_new_tokens(engine, 48)     // 从 32 升为 48，长句不截断
```

**调参效果说明**：

| 参数 | 降低值的效果 | 升高值的效果 |
|------|------------|------------|
| chunk_sec | 首字延迟降低，但识别精度可能下降 | 首字延迟升高，精度更稳定 |
| rollback | 回滚开销减少，但文本稳定性降低 | 文本更稳定，但响应变慢 |
| unfixed_chunks | 文本更快确认输出，但可能有更多修正 | 文本更稳定，延迟更高 |
| max_new_tokens | 长句可能被截断 | 允许更长的单次输出 |

**建议**：提供设置界面或 UserDefaults 存储这些参数，方便不同场景下调优。

---

### 方案 2：推理线程数动态适配

**难度**：低 | **收益**：低-中 | **需改 Rust**：否

#### 问题

当前 `numThreads` 硬编码为 4（`QwenASRRecognizer.swift:12`），无法充分利用高性能 Mac 的多核心：

| 芯片 | P 核 | E 核 | 总核心 | 当前使用 | 利用率 |
|------|------|------|--------|---------|--------|
| M1 | 4 | 4 | 8 | 4 | 50% |
| M1 Pro | 8 | 2 | 10 | 4 | 40% |
| M2 Pro | 6 | 4 | 10 | 4 | 40% |
| M3 Pro | 6 | 6 | 12 | 4 | 33% |
| M4 Pro | 10 | 4 | 14 | 4 | 29% |

#### 建议

根据 CPU 核心数动态计算，优先使用 P 核（性能核心）：

```swift
// QwenASRRecognizer.swift init() 中替换硬编码的 numThreads
let activeProcessors = ProcessInfo.processInfo.activeProcessorCount
let optimalThreads = Int32(max(4, min(activeProcessors / 2, 8)))
engine = qwen_asr_load_model(modelDir, optimalThreads, 0)
```

**上限设为 8 的原因**：线程过多反而因调度开销降低吞吐。对于 Transformer 推理，通常 P 核数量是最优值。

> 注意：`qwen_asr.h:15` 文档说明 `n_threads <= 0` 时会自动检测，可以先测试传 0 或 -1 让 Rust 侧自行决策是否效果更好。

---

### 方案 3：缩短 Flush 静音填充

**难度**：低 | **收益**：中（减少 1-1.5s 延迟） | **需改 Rust**：需测试

#### 问题

每次录音结束，需要推送 2 秒静音才能触发 finalize：

```swift
// ASREngine.swift:192
let silencePadding = [Float](repeating: 0.0, count: 32000)  // 2秒 @ 16kHz
_ = self.recognizer.pushAudio(samples: silencePadding, finalize: true)
```

这导致用户松开按键后，还要等约 2 秒才能拿到最终结果。

#### 建议

**实验 1**：缩短静音长度，测试最小可行值：

```swift
// 逐步测试：16000 (1s) → 8000 (0.5s) → 4000 (0.25s)
let silencePadding = [Float](repeating: 0.0, count: 8000)  // 0.5秒
```

**实验 2**：既然 `finalize=1` 参数已经明确告知 Rust 端要结束，理论上不需要那么长的静音。测试直接传空或极短 buffer：

```swift
// 最激进方案：只传 finalize 标志，不补静音
_ = self.recognizer.pushAudio(samples: [], finalize: true)
```

**实验 3**：对比 Streaming Paraformer 的 flush 策略，它只用了 4800 样本（0.3s）：

```swift
// ASREngine.swift:138 — Paraformer 的 flush
let silencePadding = [Float](repeating: 0.0, count: 4800)  // 仅 0.3s
```

同样是流式引擎，Paraformer 只需 0.3s 而 Qwen3-ASR 需要 2s，值得验证 Qwen3-ASR 是否真的需要这么长。

---

### 方案 4：音频 Buffer 累积策略

**难度**：低 | **收益**：低 | **需改 Rust**：否

#### 问题

当前每次音频回调（约 0.256s 的数据）都会触发一次 FFI 调用。对于 chunk 大小为 2s 的流式推理，前 7-8 次 `pushAudio` 调用实际上只是在 Rust 侧累积数据，并不会产出结果。

#### 建议

在 Swift 侧累积 buffer，攒够一定量再调 FFI，减少跨语言调用的开销：

```swift
// 在 QwenASREngine 中添加累积逻辑
private var audioBuffer: [Float] = []
private let minPushSize = 16000  // 累积 1 秒再推

func processAudio(samples: [Float], onPartialResult: @escaping (String) -> Void) {
    audioBuffer.append(contentsOf: samples)
    guard audioBuffer.count >= minPushSize else { return }

    let chunk = audioBuffer
    audioBuffer.removeAll(keepingCapacity: true)

    recognitionQueue.async { [weak self] in
        if let _ = self?.recognizer.pushAudio(samples: chunk, finalize: false) {
            let fullText = self?.recognizer.getResult() ?? ""
            if !fullText.isEmpty { onPartialResult(fullText) }
        }
    }
}
```

**注意**：这会增加实时反馈的延迟（多等 1s），需要根据实际体验权衡。如果用户对"打字实时跳出"很敏感，可以降低 `minPushSize` 或保持现状。

---

### 方案 5：Rust 侧启用 Metal GPU 加速

**难度**：高 | **收益**：高 | **需改 Rust**：是

#### 问题

`libqwen_asr.dylib` 仅 689KB，本身不包含推理框架代码。它可能依赖：
- [candle](https://github.com/huggingface/candle)（Rust 原生 ML 框架）
- [llama.cpp / ggml](https://github.com/ggerganov/llama.cpp)（通过 Rust FFI）
- 自定义推理实现

无论使用哪种后端，如果当前**仅在 CPU 上推理**，那么 Apple Silicon 的 GPU 和 Neural Engine 完全闲置。

#### Apple Silicon 计算资源

| 计算单元 | M1 | M3 Pro | M4 Pro |
|---------|-----|--------|--------|
| CPU (TOPS) | ~2 | ~3 | ~4 |
| GPU (TFLOPS) | 2.6 | 4.4 | 5.3 |
| Neural Engine (TOPS) | 11 | 18 | 38 |
| 统一内存带宽 | 68 GB/s | 150 GB/s | 273 GB/s |

Transformer 推理是**内存带宽受限**任务（尤其是 decode 阶段），Metal GPU 可以更高效地利用统一内存带宽。

#### 可能的方案

**方案 A：candle + Metal 后端**

如果 Rust 侧使用 candle 框架，它已支持 Metal 后端：

```rust
// Rust 侧代码修改（伪代码）
use candle_core::Device;

// 当前可能是：
let device = Device::Cpu;

// 改为：
let device = Device::new_metal(0)?;  // 使用 Metal GPU
```

**方案 B：llama.cpp Metal 后端**

如果使用 ggml/llama.cpp，可以启用 Metal 加速：

```c
// 需在编译时启用 GGML_USE_METAL
struct ggml_context * ctx = ggml_init(params);
// Metal 后端会自动用于大矩阵运算
```

**方案 C：将模型转为 GGUF 格式 + llama.cpp**

如果当前推理后端性能一般，可以考虑将 Qwen3-ASR 的权重转为 GGUF 格式，通过 llama.cpp 的 Metal 后端推理。llama.cpp 已支持很多 Qwen 系列模型。

#### 预期收益

以 Qwen3-ASR-0.6B 为例，decode 阶段（28 层 Transformer，hidden_size=1024）：

| 场景 | 预估推理速度 |
|------|------------|
| CPU 4 线程 (当前) | ~20-40 tokens/s |
| Metal GPU | ~60-120 tokens/s |
| Metal + 量化 (INT4) | ~100-200 tokens/s |

> 以上为估算值，实际性能取决于具体推理后端实现。

#### 前置调查

实施前需要先确认 Rust 侧使用的推理后端：

```bash
# 查看 dylib 的动态依赖
otool -L Frameworks/qwen-asr/lib/libqwen_asr.dylib

# 查看导出的符号（推断使用了什么框架）
nm -gU Frameworks/qwen-asr/lib/libqwen_asr.dylib | head -50
```

---

### 方案 6：模型量化降级

**难度**：中 | **收益**：中 | **需改 Rust**：需测试兼容性

#### 问题

当前使用的 Qwen3-ASR-0.6B 模型以 SafeTensors 格式存储，大小约 1.2GB。如果 Rust 推理后端支持量化推理，可以用更小的模型换取更快的速度。

#### 量化选项

| 量化方式 | 模型大小 (估算) | 精度损失 | 速度提升 |
|---------|---------------|---------|---------|
| BF16 (当前) | ~1.2 GB | 基准 | 基准 |
| INT8 | ~600 MB | 极小 (WER +0.1~0.3) | ~1.5-2x |
| INT4 | ~350 MB | 小 (WER +0.3~0.8) | ~2-3x |

#### 前提条件

需要确认 Rust 推理后端是否支持量化权重格式。如果使用 candle，它支持 GGUF 量化格式。

---

## 三、优化优先级排序

| 优先级 | 方案 | 难度 | 预期收益 | 风险 |
|--------|------|------|---------|------|
| **P0** | 方案 1：暴露流式参数 | 低 | 降低出字延迟 0.5-1s | 极低 |
| **P0** | 方案 3：缩短 flush 静音 | 低 | 降低结束延迟 1-1.5s | 需验证 |
| **P1** | 方案 2：动态线程数 | 低 | 高性能机器提速 20-50% | 极低 |
| **P2** | 方案 5：Metal GPU 加速 | 高 | 推理速度 2-5x | 需改 Rust 源码 |
| **P2** | 方案 6：模型量化 | 中 | 速度 1.5-2x + 内存减半 | 精度损失 |
| **P3** | 方案 4：Buffer 累积 | 低 | 微小 | 增加延迟 |

---

## 四、实施建议

### 第一阶段：Swift 侧快速优化 (不改 Rust)

1. 在 `QwenASRStreamRecognizer.init()` 中调用流式参数配置函数
2. 动态计算推理线程数
3. 测试缩短 flush 静音填充长度

### 第二阶段：Rust 侧深度优化

1. 用 `otool -L` 和 `nm` 确认推理后端类型
2. 评估 Metal GPU 加速的可行性
3. 测试量化模型的精度与速度

### 第三阶段：性能基准测试

建立标准化测试流程，对比优化前后：

| 指标 | 测试方法 |
|------|---------|
| 首字延迟 (TTFT) | 从音频开始到第一个字符输出的时间 |
| 结束延迟 | 从停止录音到最终结果输出的时间 |
| 吞吐量 | 每秒处理的音频时长 (RTF) |
| 内存占用 | 推理期间的峰值内存 |
| WER/CER | 标准测试集上的识别准确度 |

可以利用项目中已有的 E2E 测试 (`Tests/QwenASRE2ETests.swift`) 中的 `testPerformanceBaseline()` 作为基准。

---

## 五、参考

- C FFI 接口定义：`Frameworks/qwen-asr/include/qwen_asr.h`
- Swift 包装层：`Sources/QwenASRRecognizer.swift`
- 引擎封装：`Sources/ASREngine.swift:162-207`
- 音频采集：`Sources/RecordingManager.swift:265`
- E2E 测试：`Tests/QwenASRE2ETests.swift`
- Rust 编译产物：`Frameworks/qwen-asr/lib/libqwen_asr.dylib` (689KB) / `libqwen_asr.a` (17MB)
