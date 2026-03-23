# Telemetry Schema Design — v1 (Free TelemetryDeck)

## 设计原则

1. **Quota 优先**：免费 TelemetryDeck 有用量限制，每次录音最多触发 4 个事件
2. **精确 ms**：延迟使用精确毫秒值（非 bucket），最大化诊断价值
3. **合并优于拆分**：子阶段延迟合并到 `PostProcessing.Completed` 中，不拆独立事件
4. **隐私保护**：文本长度 bucket 化，绝不发送原始文本

## 事件总览

| # | 事件名 | 触发时机 | 频率 | 版本 |
|---|--------|---------|------|------|
| 1 | `App.Launched` | 应用启动 | 每次启动 1 次 | v1.0 已有 |
| 2 | `Model.LoadCompleted` | 模型加载完成 | 启动/切换引擎时 | **v1.1 新增** |
| 3 | `Session.Completed` | 录音会话结束 | 每次录音 1 次 | v1.0 已有 |
| 4 | `ASR.FlushCompleted` | ASR 引擎 flush 完成 | 每次录音 1 次 | **v1.1 新增** |
| 5 | `PostProcessing.Completed` | 后处理管道完成 | 每次录音 1 次 | v1.0 → **v1.1 增强** |
| 6 | `CloudRewrite.Completed` | 云端重写完成 | 每次录音 1 次 | v1.0 已有 |

**每次录音消耗**：4 个事件（Session + ASR.Flush + PostProcessing + CloudRewrite）

## 通用维度（所有事件自动附加）

由 `AnalyticsService.track()` 自动注入：

| 参数 | 说明 | 示例 |
|------|------|------|
| `appVersion` | Bundle 版本号 | `"1.5.0"` |
| `selectedEngine` | 当前 ASR 引擎 | `"streamingParaformer"` |
| `cloudRewriteEnabled` | Cloud Rewrite 是否启用 | `"true"` |

## 事件详细定义

### 1. App.Launched

应用启动时发送，用于统计 DAU。

```json
{
  "event": "App.Launched",
  "parameters": {}
}
```

仅通用维度，无额外参数。

### 2. Model.LoadCompleted (v1.1 新增)

模型加载完成（成功或失败）时发送。覆盖引擎创建 + 子模型（标点/CSC/ITN/TermNorm）加载的总耗时。

```json
{
  "event": "Model.LoadCompleted",
  "parameters": {
    "engine": "streamingParaformer",
    "latencyMs": "2345",
    "success": "true",
    "errorType": "load_failed"
  }
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `engine` | string | 引擎类型：`streamingParaformer` / `qwenASR` / `dualEngine` |
| `latencyMs` | string(int) | 精确加载耗时（毫秒） |
| `success` | string(bool) | 是否加载成功 |
| `errorType` | string | 失败时的错误类型（成功时不发送） |

### 3. Session.Completed (已有)

录音会话结束时发送。

```json
{
  "event": "Session.Completed",
  "parameters": {
    "engine": "streamingParaformer",
    "durationBucket": "5-15s",
    "hasResult": "true",
    "resultLengthBucket": "11-50"
  }
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `engine` | string | 引擎类型 |
| `durationBucket` | string | 录音时长桶：`0-5s` / `5-15s` / `15-30s` / `30-60s` / `60s+` |
| `hasResult` | string(bool) | 是否产生识别结果 |
| `resultLengthBucket` | string | 结果文本长度桶：`0` / `1-10` / `11-50` / `51-200` / `200+` |

### 4. ASR.FlushCompleted (v1.1 新增)

ASR 引擎 flush 完成时发送。这是 ASR 核心性能指标——从停止录音到获取最终识别文本的耗时。

```json
{
  "event": "ASR.FlushCompleted",
  "parameters": {
    "engine": "streamingParaformer",
    "latencyMs": "187",
    "success": "true",
    "rawTextLengthBucket": "11-50"
  }
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `engine` | string | 引擎类型 |
| `latencyMs` | string(int) | 精确 flush 耗时（毫秒） |
| `success` | string(bool) | flush 是否返回了非空文本 |
| `rawTextLengthBucket` | string | 原始文本长度桶 |

### 5. PostProcessing.Completed (v1.1 增强)

后处理管道完成时发送。**包含每个子阶段的精确延迟**，一个事件即可定位 pipeline 瓶颈。

```json
{
  "event": "PostProcessing.Completed",
  "parameters": {
    "itnApplied": "true",
    "cscApplied": "true",
    "punctuationApplied": "true",
    "totalLatencyMs": "1523",
    "termNormLatencyMs": "2",
    "itnLatencyMs": "15",
    "cscLatencyMs": "89",
    "punctLatencyMs": "156",
    "cloudRewriteLatencyMs": "1261",
    "termNormChanged": "false"
  }
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `itnApplied` | string(bool) | ITN 是否修改了文本 |
| `cscApplied` | string(bool) | CSC 是否修改了文本 |
| `punctuationApplied` | string(bool) | 标点是否修改了文本 |
| `totalLatencyMs` | string(int) | Pipeline 总耗时（毫秒） |
| `termNormLatencyMs` | string(int) | TermNormalizer 耗时 |
| `itnLatencyMs` | string(int) | ITN 耗时（未启用时为 `"0"`） |
| `cscLatencyMs` | string(int) | CSC 耗时（未启用时为 `"0"`） |
| `punctLatencyMs` | string(int) | 标点处理耗时（未启用时为 `"0"`） |
| `cloudRewriteLatencyMs` | string(int) | Cloud Rewrite 耗时 |
| `termNormChanged` | string(bool) | TermNormalizer 是否修改了文本 |

### 6. CloudRewrite.Completed (已有)

Cloud Rewrite 完成时发送。已有完善的错误分类。

```json
{
  "event": "CloudRewrite.Completed",
  "parameters": {
    "outcome": "rewritten",
    "latencyBucket": "500-1000ms",
    "model": "gpt-oss-120b",
    "changed": "true",
    "inputLengthBucket": "11-50",
    "errorType": "network_timeout"
  }
}
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `outcome` | string | 结果：`rewritten` / `timeout` / `error` / `noApiKey` |
| `latencyBucket` | string | 延迟桶（成功时） |
| `model` | string | 使用的模型（成功时） |
| `changed` | string(bool) | 文本是否被修改（成功时） |
| `inputLengthBucket` | string | 输入文本长度桶 |
| `errorType` | string | 错误类型（失败时） |

## 延迟测量链路

```
用户按下录音键
    │
    ├─ Session.Started (仅计时起点，不发事件)
    │
    ├─ [录音中 ... 流式识别]
    │
    ├─ 用户松开录音键
    │   └─ ASR.FlushCompleted        ← flush 延迟
    │
    ├─ PostProcessing Pipeline
    │   ├─ TermNormalizer             ← termNormLatencyMs
    │   ├─ ITN                        ← itnLatencyMs
    │   ├─ CSC                        ← cscLatencyMs
    │   ├─ Punctuation                ← punctLatencyMs
    │   └─ CloudRewrite               ← cloudRewriteLatencyMs
    │       └─ CloudRewrite.Completed
    │   └─ PostProcessing.Completed   ← totalLatencyMs (含所有子阶段)
    │
    └─ Session.Completed              ← 会话总时长 (durationBucket)
```

## 隐私保护

- **绝对禁止**：任何原始文本内容
- **延迟值**：使用精确 ms（非 PII，无隐私风险）
- **文本长度**：bucket 化处理（`0` / `1-10` / `11-50` / `51-200` / `200+`）
- **用户控制**：opt-out 机制（UserDefaults `analyticsEnabled`）
- **DEBUG 标记**：TelemetryDeck 自动区分测试/生产信号

## v2 扩展预留（付费 TelemetryDeck 后启用）

以下事件已在代码中预留架构，但当前不发送：

| 事件 | 说明 | 原因 |
|------|------|------|
| `ASR.PartialResult` | 流式中间结果 | 高频（每秒多次），消耗大量 quota |
| `ASR.ProcessingStarted` | ASR 处理开始 | 与 FlushCompleted 配对时才有价值 |
| `Session.Started` | 录音开始 | 与 Session.Completed 配对，当前只需一端 |
| `TermNormalizer.Completed` | 独立阶段事件 | 已合并到 PostProcessing.Completed |
| `ITN.Completed` | 独立阶段事件 | 已合并到 PostProcessing.Completed |
| `CSC.Completed` | 独立阶段事件 | 已合并到 PostProcessing.Completed |
| `Punctuation.Completed` | 独立阶段事件 | 已合并到 PostProcessing.Completed |
| `VAD.ProcessingCompleted` | VAD 检测 | 当前无 VAD 模块 |

## 代码实现参考

### 延迟测量（使用 `ContinuousClock`）

```swift
// 方式 1：使用 AnalyticsService 辅助函数
let start = ContinuousClock.now
// ... work ...
let ms = AnalyticsService.elapsedMs(since: start)
AnalyticsService.track("Event.Name", parameters: ["latencyMs": "\(ms)"])
```

### 修改的文件清单

| 文件 | 改动 |
|------|------|
| `Sources/AnalyticsService.swift` | 新增 `elapsedMs(since:)` 辅助函数、`fineLatencyBucket(ms:)` |
| `Sources/PostProcessingPipeline.swift` | 每个子阶段加 `ContinuousClock` 计时，传精确 ms 到事件 |
| `Sources/RecordingManager.swift` | flush 路径加 `ASR.FlushCompleted` 埋点 |
| `Sources/ASREngineFactory.swift` | 模型加载路径加 `Model.LoadCompleted` 埋点 |

---

*文档版本: v1.1*
*最后更新: 2026-03-23*
