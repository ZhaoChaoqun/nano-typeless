# Bug Report #001: 跨会话状态泄露 & CSC 过度纠正

*2026-03-01*

---

## 概述

E2E 测试中发现两个关键缺陷，均在 Streaming Paraformer 引擎下复现：

| Bug | 严重度 | 现象 |
|-----|--------|------|
| #1 State Bleeding | Critical | 上一次录音的尾部 token 泄露到下一次录音的开头 |
| #2 CSC Overcorrection | High | macbert4csc 将"真不错"纠正为"真不棒"（语义替换而非纠错） |

Bug #2 部分由 Bug #1 引发：泄露的"一"污染了句子上下文，导致 BERT MLM 预测异常。

---

## Bug #1: 跨会话状态泄露 (State Bleeding)

### 复现步骤

1. 选择 Streaming Paraformer 引擎
2. 按住 Fn 说"我的 IP 地址是 192.168.1"，松开 Fn
3. 立刻再按住 Fn 说"今天天气真不错，我们可以买一些好看的花儿吗？"，松开 Fn

### 实际结果

第二次录音的原始文本以"一"开头：

```
原始文本: 一今天天气真不错我们可以买一些好看的花儿
```

上一次的数字"1"泄露为中文"一"。

### 根因分析

#### 调用链

```
Fn 松开 → KeyMonitor.onKeyUp → TypelessApp.stopRecordingAndTranscribe()
         → RecordingManager.stopRecording()
             → engine.flush() [异步，在 recognitionQueue 上]
                 → 送入 4800 样本静音 padding
                 → decode remaining frames
                 → getResult()
                 → recognizer.reset()  ← 异步完成
         → 方法立刻返回

Fn 按下 → KeyMonitor.onKeyDown → TypelessApp.startRecording()
         → RecordingManager.startRecording()
             → accumulatedText = ""
             → currentEngine?.reset()  ← 在 main queue 上
                 → recognizer.reset()
                     → SherpaOnnxOnlineStreamReset(recognizer, stream)
             → audioEngine.start()
             → 新音频开始流入同一个 stream
```

#### 根本原因：`SherpaOnnxOnlineStreamReset` 不清除特征缓冲区

`SherpaOnnxOnlineRecognizer.reset()` 调用 `SherpaOnnxOnlineStreamReset(recognizer, stream)`。sherpa-onnx 的这个 API **仅重置解码器内部状态（CTC/attention 解码器的 hypothesis），但不销毁/重建底层的特征提取管线（Fbank 等）**。

在上一次录音中，音频引擎持续送入数据直到被 `removeTap` 停止。在 `stopRecording` 和 `flush` 之间，可能有尾部音频帧已经进入了 stream 的特征缓冲区但尚未被解码。`reset()` 不清除这些帧，新会话开始时它们被当作新音频的前缀参与解码。

上一次输出末尾包含"1"（ITN 转换后的数字），尾部 audio buffer 中残留的特征对应该数字的发音。新会话解码时，这些残留特征被解码为"一"（中文 token 而非 ITN 后的阿拉伯数字，因为 ITN 在 getResult 时应用）。

#### 加剧因素：竞态条件

`stopRecording()` 中的 `engine.flush()` 是在 `recognitionQueue` 上异步执行的。如果用户快速连续按键，`startRecording()` 可能在 flush 完成之前被调用，此时 flush 内部的 `reset()` 和 `startRecording()` 中的 `reset()` 会竞争同一个 stream 对象。

### 修复方案

**核心修复：在 `reset()` 中销毁旧 stream 并创建新 stream**

`SherpaOnnxOnlineRecognizer.swift`:

```swift
func reset() {
    guard let recognizer = recognizer else { return }
    // 销毁旧 stream（清除所有缓冲区）
    if let stream = stream {
        SherpaOnnxDestroyOnlineStream(stream)
    }
    // 创建全新的 stream
    stream = SherpaOnnxCreateOnlineStream(recognizer)
}
```

这确保所有残留的音频特征、解码器状态被彻底清除。

**辅助修复：防止竞态**

在 `RecordingManager.startRecording()` 中，确保 `reset()` 也在 `recognitionQueue` 上执行，与 flush 串行化：

```swift
func startRecording() {
    guard !isRecording else { return }
    accumulatedText = ""
    // 在 recognitionQueue 上同步执行 reset，确保与 flush 串行化
    recognitionQueue.sync {
        currentEngine?.reset()
    }
    // ... 创建音频引擎并启动
}
```

---

## Bug #2: CSC 过度纠正 (Overcorrection)

### 复现现象

```
输入: 一今天天气真不错我们可以买一些好看的花儿
CSC:  一今天天气真不棒我们可以买一些好看的花儿
```

"错" (cuò) 被替换为 "棒" (bàng)。这不是同音字纠错，而是语义替换。

### 根因分析

#### 位置：`ChineseSpellingCorrector.swift:245`

```swift
if logitDiff > 2.0 {
    // 执行替换
}
```

#### 问题 1：logit 差值阈值过低

macbert4csc 输出的 logit 范围通常在 [-10, +30]。`logitDiff > 2.0` 意味着只要模型对替换字符**稍微**比原字符有信心，就会执行替换。

对于"真不错"场景：模型收到异常上下文"一今天天气真不X..."，其中 X 位置的 logit 分布可能因上下文污染而异常，导致"棒"的 logit 略高于"错"超过 2.0。

#### 问题 2：缺乏纠正比例上限

当前没有 sanity check 限制单次纠正的字符数量。如果 CSC 纠正了超过一定比例的字符（如 >30%），说明输入本身有问题（如 Bug #1 的上下文污染），应该丢弃纠正结果返回原文。

#### 问题 3：用 logit 差值而非概率

logit 差值和实际概率差距不是线性关系。更可靠的方式是比较 softmax 后的概率。

### 修复方案

1. **提高 logit 差值阈值**：从 2.0 提高到 5.0，要求更高置信度
2. **添加纠正比例上限**：单次纠正的中文字符数不超过总中文字符数的 20%，超过则丢弃纠正返回原文
3. **添加 softmax 概率差值检查**：计算 top-1 的 softmax 概率，只有当概率 > 0.9 时才考虑替换

---

## 修复影响范围

| 文件 | 修改内容 |
|------|---------|
| `Sources/SherpaOnnxOnlineRecognizer.swift` | `reset()` 销毁旧 stream 并创建新 stream |
| `Sources/RecordingManager.swift` | `startRecording()` 在 recognitionQueue 上同步 reset |
| `Sources/ChineseSpellingCorrector.swift` | 提高阈值 + 添加纠正比例限制 |

---

## 验证计划

### Bug #1 验证

1. 选择 Streaming Paraformer
2. 说"我的手机号码是 18510060048"，松开 Fn
3. 立刻按 Fn 说"今天天气真不错"，松开 Fn
4. 确认第二次原始文本不以"一"或数字开头

### Bug #2 验证

1. 输入"今天天气真不错我们可以买一些好看的花儿"
2. 确认 CSC 不修改任何字符（此句无拼写错误）
3. 输入"今天天汽真不错"（"汽"是"气"的同音字错误）
4. 确认 CSC 纠正"汽"→"气"，不触碰其他字符
