# FunASR Nano LLM 跨录音会话数据泄漏 Bug

## 现象

使用 FunASR Nano LLM 引擎时，连续两次录音的第二次转录结果**包含了第一次的完整内容**。

### 复现步骤

1. 按住 Fn 键录音第一句："请先生成你的实现计划，如果有需要我进一步确认的地方，可以随时向我提问。"
2. 松开 Fn 键，等待转录完成 → 结果正确
3. 再次按住 Fn 键录音第二句："嗯，可以帮我把本地暂未提交的代码合成比较合理的commit，然后部署到远端吗？"
4. 松开 Fn 键 → **结果错误**，输出为第一句 + 第二句的拼接

### 实际输出

```
请先生成你的实现计划，如果有需要我进一步确认的地方，可以随时向我提问。嗯，可以帮我把本地暂未提交的代码合成比较合理的可密的，然后部署到圆团吗？
```

---

## 根因分析

### 核心问题

`FunASRNanoLLMEngine` 的 `_accumulatedText` 缓冲区和 VAD 内部状态在两次录音之间**从未被重置**。`reset()` 方法存在但从未被调用。

### 数据流追踪

```
第一次录音
─────────────────────────────────────────────────────────────
Fn 按下 → .ready → .recording
                    │
                    ▼
            processAudio() → vad.acceptWaveform()
                              → vad.popSegmentWithTime()
                              → recognizer.transcribe()
                              → _accumulatedText = "请先生成..."
                    │
Fn 松开 → .recording → .flushing
                       │
                       ▼
                 flush() → vad.flush()
                         → 处理剩余 VAD 段
                         → 返回 _accumulatedText
                    │
                    ▼
            .flushing → .postProcessing → .ready
                                          │
                                    ❌ 未调用 reset()
                                    ❌ _accumulatedText 仍 = "请先生成..."
                                    ❌ VAD 内部缓冲区未清空

第二次录音
─────────────────────────────────────────────────────────────
Fn 按下 → .ready → .recording
                    │
                    ▼
            processAudio() → vad.acceptWaveform()
                              → vad.popSegmentWithTime()
                              → recognizer.transcribe() → 新文本
                              → _accumulatedText += 新文本   ← BUG！旧数据仍在
                    │
                    ▼
            flush() → 返回 "第一句 + 第二句"
```

### 涉及代码

#### 1. `FunASRNanoLLMEngine.flush()` — 不清理状态

**文件:** `Sources/ASREngine.swift:120-143`

```swift
func flush(completion: @escaping (String) -> Void) {
    vad.flush()
    recognitionQueue.async { [weak self] in
        // ... 处理剩余 VAD 段 ...
        let rawText = self.internalQueue.sync { self._accumulatedText }
        DispatchQueue.main.async { completion(rawText) }
        // ❌ 此处缺少 reset() 调用
    }
}
```

`flush()` 读取并返回 `_accumulatedText`，但**不清空它**。下次录音时旧数据仍然存在。

#### 2. `FunASRNanoLLMEngine.reset()` — 存在但从未被调用

**文件:** `Sources/ASREngine.swift:145-148`

```swift
func reset() {
    vad.reset()
    internalQueue.sync { _accumulatedText = "" }
}
```

`reset()` 实现是正确的——重置 VAD 并清空累积文本。但在整个录音生命周期中**从未被调用**。

#### 3. `RecordingManager.handleSideEffects()` — 状态转换缺失 reset

**文件:** `Sources/RecordingManager.swift:132-135`

```swift
// 后处理完成
case (.postProcessing, .ready):
    if case .postProcessComplete(let finalText) = event {
        DispatchQueue.main.async { self.onFinalResult?(finalText) }
    }
    // ❌ 此处缺少 currentEngine?.reset()
```

这是两次录音之间的唯一过渡点（`.postProcessing → .ready`），但没有调用引擎的 `reset()`。

#### 4. `startAudioEngine()` — 也不调用 reset

**文件:** `Sources/RecordingManager.swift:144-176`

`startAudioEngine()` 只创建新的 `AVAudioEngine` 和安装 tap，不涉及 ASR 引擎的状态重置。

---

## 影响范围

| 引擎 | 是否受影响 | 原因 |
|------|:---------:|------|
| FunASR Nano LLM | **是** | `_accumulatedText` 跨会话累积 |
| Qwen3-ASR 流式 | 否 | `flush()` 内部调用了 `recognizer.reset()` |
| Paraformer | 否 | `flush()` 内部调用了 `recognizer.reset()` |

对比 `QwenASREngine.flush()`（`ASREngine.swift:195-215`）可以看到，Qwen 引擎在 flush 末尾调用了 `self.recognizer.reset()`，所以不受此 bug 影响。

---

## 修复方案

在 `FunASRNanoLLMEngine.flush()` 的 completion 回调后调用 `self.reset()`：

```swift
func flush(completion: @escaping (String) -> Void) {
    vad.flush()
    recognitionQueue.async { [weak self] in
        guard let self = self else { ... }
        // ... 处理剩余 VAD 段 ...
        let rawText = self.internalQueue.sync { self._accumulatedText }
        self.reset()  // ← 修复：flush 完成后重置状态
        DispatchQueue.main.async { completion(rawText) }
    }
}
```

这与 `QwenASREngine` 和 `ParaformerEngine` 的行为保持一致。

---

## 时间线

- **发现时间:** 2026-03-04 18:09
- **影响版本:** FunASR Nano LLM 引擎引入以来的所有版本
- **严重程度:** 高（输出错误结果，用户可感知）
