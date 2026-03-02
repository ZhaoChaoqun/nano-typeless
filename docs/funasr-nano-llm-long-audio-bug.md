# FunASR Nano LLM 长音频空输出 Bug 分析

## 现象

Benchmark 测试中，FunASR Nano LLM 对两条长音频条目输出完全为空：

| 条目 | 音频时长 | CER | 实际输出 |
|------|---------|-----|---------|
| `long_30s_01` | ~43s | 0.995 | `对。`（仅 2 字） |
| `long_60s_01` | ~75s | 1.000 | （完全空） |

短音频（如 `zh_short_01`）CER=0.000，工作完全正常。

## 根因分析

问题出在 **Benchmark 测试代码**，而非 FunASR Nano LLM 引擎本身。

### 1. Benchmark 直接整段送入，缺少 VAD 分段

Benchmark 测试的原始逻辑是：

```swift
// 短音频直接整段识别
return recognizer.transcribe(samples: samples) ?? ""
```

所有音频不论长短，都被整段送入 `FunASRNanoLLMRecognizer.transcribe()`。

FunASR Nano LLM 的 encoder（SenseVoice）有 **上下文长度限制**，无法处理 30s+ 的连续音频。当输入超出限制时，模型内部截断或产生退化输出。

对比：**产品代码**（`FunASRNanoLLMEngine`）始终通过 VAD 分段后再逐段送入 recognizer，因此工作正常。

### 2. 首次 VAD 修复：一次性送入全部 samples → 缓冲区溢出

第一次修复尝试在 benchmark 中加入 VAD，但采用了一次性送入的方式：

```swift
// 错误：一次性送入全部音频
vad.acceptWaveform(samples: allSamples)  // 43 秒 = 688,000 个 samples
```

结果 VAD 从 43 秒的音频中只检测到 **1 个 0.16 秒的片段**，输出 `对。`。

原因：Silero VAD 在创建时指定了 **5 秒的内部环形缓冲区**：

```swift
// SherpaOnnxVAD.swift:45
vad = SherpaOnnxCreateVoiceActivityDetector(&config, 5.0)
```

当一次性灌入 688,000 个 samples（43 秒），远超 5 秒缓冲区（80,000 samples）。VAD 内部缓冲区溢出，绝大部分音频数据被丢弃，只在缓冲区残留数据中检测到一个极短片段。

### 3. 最终修复：模拟产品代码的分块送入

产品代码中，音频来自麦克风 `installTap`，每次回调约 4096 个 samples（~0.256 秒），天然是小块送入 VAD。Benchmark 需要模拟同样的行为。

## 修复方案

对 `testFunASRNanoLLMPipeline` 添加长音频分支，以 4096 samples 为单位分块送入 VAD：

```swift
if samples.count >= 25 * 16000, let vad = vadForLLM {
    vad.reset()
    let chunkSize = 4096
    var accumulated = ""

    // 分块送入 VAD（模拟麦克风输入）
    for i in stride(from: 0, to: samples.count, by: chunkSize) {
        let end = min(i + chunkSize, samples.count)
        let chunk = Array(samples[i..<end])
        vad.acceptWaveform(samples: chunk)

        // 及时取出已检测到的语音段
        while vad.hasSegment() {
            if let segment = vad.popSegmentWithTime() {
                if let text = recognizer.transcribe(samples: segment.samples) {
                    accumulated += text
                }
            }
        }
    }

    // flush 取出末尾残留片段
    vad.flush()
    while vad.hasSegment() {
        if let segment = vad.popSegmentWithTime() {
            if let text = recognizer.transcribe(samples: segment.samples) {
                accumulated += text
            }
        }
    }

    return accumulated
}
```

关键要点：
- **分块大小 4096**：与产品代码 `installTap` 一致，确保不超过 VAD 缓冲区
- **边送边取**：每送入一个 chunk 后立即检查 `hasSegment()`，避免已检测到的段在 VAD 内部堆积
- **flush 收尾**：送完所有数据后调用 `vad.flush()` 强制输出最后一个语音段
- **阈值 25 秒**：短音频仍走直接识别路径，仅长音频需要 VAD

## 修复结果

| 条目 | 修复前 CER | 修复后 CER |
|------|-----------|-----------|
| `long_30s_01` (43s) | 0.995 | **0.046** |
| `long_60s_01` (75s) | 1.000 | **0.062** |
| 平均 | ~1.000 | **0.054** |

## 经验总结

1. **Silero VAD 内部缓冲区有限**（由 `bufferSizeInSeconds` 参数控制，本项目为 5 秒）。大量音频必须分块送入，不能一次性灌入。

2. **Benchmark 测试要模拟产品代码的数据流**。产品代码通过麦克风回调天然分块，而 benchmark 从文件一次性加载全部 samples，如果直接送入会跳过产品代码中隐含的分块逻辑。

3. **离线 ASR 模型有输入长度上限**。FunASR Nano LLM 的 SenseVoice encoder 上下文窗口有限，超长音频必须 VAD 分段后逐段识别——这是产品代码设计 `FunASRNanoLLMEngine` 时就已处理的，但 benchmark 绕过了 engine 层直接调用 recognizer。
