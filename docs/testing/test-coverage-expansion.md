# Qwen3-ASR 测试覆盖文档

> 当前状态: **69 个测试全部通过** (4 个测试类)

## 测试套件总览

| 测试类 | 测试数量 | 说明 | 需要模型 |
|--------|---------|------|---------|
| `QwenASRE2ETests` | 37 | 端到端识别质量验证 (Edge-TTS 语料) | 是 |
| `QwenASRBoundaryTests` | 9 | 边界条件 & 内存增长 | 是 |
| `QwenASRConcurrencyTests` | 4 | 并发安全 & 线程竞态 | 是 |
| `QwenASRUnitTests` | 13 | Mock 单元测试 | 否 |

---

## 一、E2E 测试 (`QwenASRE2ETests`) — 37 个测试

语料来源: `tests/fixtures/corpus.json` (35 条)，音频由 Edge-TTS (`zh-CN-XiaoxiaoNeural` / `en-US-JennyNeural`) 生成，合成音频（静音/噪声）直接生成。

### 1.1 基础识别 (9 个)

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 1 | `testChineseShort` | `zh_short_01` | 今天天气真好 | 中文短句基础识别 | CER ≤ 0.15 |
| 2 | `testChineseLong` | `zh_long_01` | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析 | 中文长句识别 + 标点生成 | CER ≤ 0.15 |
| 3 | `testMixedZhEn` | `mixed_01` | 我今天用Python写了一个API接口 | 中英混合基础识别 | 包含 `Python`, `API` |
| 4 | `testMixedTechnical` | `mixed_02` | MacBook Pro M3芯片性能提升了百分之四十 | 产品名称 + 技术术语混合 | 包含 `MacBook`, `芯片` |
| 5 | `testEnglishShort` | `en_short_01` | Hello world | 纯英文短句识别 | CER ≤ 0.2 |
| 6 | `testTechnicalNumbers` | `tech_num_01` | 服务器IP地址是192.168.1.100端口号8080 | 数字 / IP 地址识别 | 包含 `服务器`, `端口` |
| 7 | `testSilence` | `silence_01` | *(3s 静音)* | 静音不产生幻觉文本 | 空白 |
| 8 | `testShortSilence` | `silence_02` | *(0.1s 静音)* | 极短静音不崩溃 | 空白 |
| 9 | `testSpeechWithTrailingSilence` | `noise_01` | 你好 + 尾部静音 | 语音后静音不产生幻觉 | 包含 `你好` |

### 1.2 开发者术语 (8 个)

面向核心使用场景：开发者用语音输入代码相关内容。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 10 | `testDevGitCommand` | `dev_git_01` | 执行git commit修复登录bug | Git CLI 命令术语 | 包含 `git`, `commit`, `bug` |
| 11 | `testDevSwiftStruct` | `dev_swift_01` | 定义一个struct叫做UserModel | Swift 类型定义术语 | 包含 `struct` |
| 12 | `testDevRustAsync` | `dev_rust_01` | 在Rust里面用async await处理并发 | Rust 异步编程术语 | 包含 `Rust`, `async` |
| 13 | `testDevKubernetes` | `dev_k8s_01` | Kubernetes的pod状态是CrashLoopBackOff | K8s 运维术语 | 包含 `crash`, `back` |
| 14 | `testDevRESTfulAPI` | `dev_api_01` | 调用RESTful API返回JSON格式数据 | REST API + JSON 术语 | 包含 `API`, `JSON` |
| 15 | `testDevSQLQuery` | `dev_db_01` | 执行SQL查询SELECT FROM users WHERE id等于一 | SQL 关键字识别 | 包含 `SQL`, `SELECT`, `users` |
| 16 | `testDevURL` | `dev_url_01` | 访问github点com | URL 口语化表达 | 包含 `访问`, `com` |
| 17 | `testDevBreakpoint` | `dev_debug_01` | 在第四十二行设置一个breakpoint | 调试术语识别 | 包含 `breakpoint` |

### 1.3 Code-Switching 中英句内切换 (5 个)

开发者语音中频繁出现的中英句内混合场景。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 18 | `testCodeSwitchVariable` | `cs_var_01` | 把这个variable赋值给constant | 编程变量术语切换 | 包含 `variable`, `constant` |
| 19 | `testCodeSwitchBuild` | `cs_build_01` | 在macOS上运行swift build | 系统平台 + 构建命令 | 包含 `macOS`, `swift`, `build` |
| 20 | `testCodeSwitchError` | `cs_error_01` | 这个error是null pointer exception | 异常类型名称 | 包含 `error`, `pointer` |
| 21 | `testCodeSwitchDeploy` | `cs_deploy_01` | 把Docker image push到registry | 容器部署术语 | 包含 `push`, `registry` |
| 22 | `testCodeSwitchReview` | `cs_review_01` | 帮我review一下这个pull request | 代码审查流程术语 | 包含 `review`, `pull`, `request` |

### 1.4 幻觉压力测试 (4 个)

LLM-based ASR 可能对静音/噪声产生 "幻觉" 文本输出，这是关键的安全性测试。

| # | 测试方法 | 语料 ID | 输入音频 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 23 | `testHallucination10sSilence` | `hal_silence_10s` | 10s 静音 | 长静音不产生幻觉 | 空白 |
| 24 | `testHallucination30sSilence` | `hal_silence_30s` | 30s 静音 | 超长静音不产生幻觉 | 空白 |
| 25 | `testHallucinationWhiteNoise` | `hal_white_noise_01` | 3s 白噪声 | 白噪声不误识别 | 空白 |
| 26 | `testHallucinationBreathing` | `hal_breath_01` | 3s 呼吸声 | 呼吸噪声不误识别 | 空白 |

### 1.5 标点 & 格式 (3 个)

验证 Qwen3-ASR 的内置标点生成能力。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 27 | `testPunctuationQuestion` | `punct_question_01` | 你今天吃饭了吗 | 问句自动加问号 | 包含 `吃饭`, `？` |
| 28 | `testPunctuationExclamation` | `punct_exclaim_01` | 太好了我成功了 | 感叹/陈述句标点输出 | 包含 `成功`, `，` |
| 29 | `testPunctuationList` | `punct_list_01` | 第一步打开终端，第二步输入命令，第三步确认执行 | 列举句逗号分隔 | 包含 `终端`, `命令`, `，` |

### 1.6 语速变化 (2 个)

使用 macOS `say -r` 调整语速，测试 ASR 对不同语速的鲁棒性。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 30 | `testFastSpeech` | `rate_fast_01` | 快速语音识别测试一二三四五 | 快速语音 (+60%) 鲁棒性 | CER ≤ 0.2 |
| 31 | `testSlowSpeech` | `rate_slow_01` | 慢速语音识别测试 | 慢速语音 (-40%) 鲁棒性 | CER ≤ 0.15 |

### 1.7 长音频 (2 个)

测试流式缓冲区管理和长时间识别的稳定性。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 32 | `testLongAudio30s` | `long_30s_01` | 人工智能技术在过去十年中取得了巨大的进步…（约42s） | 30s+ 长音频流式识别 | 包含 `人工智能` |
| 33 | `testLongAudio60s` | `long_60s_01` | 软件工程是一门研究用工程化方法…（约77s） | 60s+ 超长音频流式识别 | 包含 `软件工程` |

### 1.8 中途停顿 (2 个)

模拟用户说话时的犹豫和停顿，通过拼接语音 + 静音 + 语音构建。

| # | 测试方法 | 语料 ID | 输入文本 | 测试目标 | 匹配模式 |
|---|---------|---------|---------|---------|---------|
| 34 | `testMidSentencePause` | `pause_mid_01` | 打开…(2s 停顿)…终端 | 句中短暂停顿不丢词 | 包含 `打开`, `终端` |
| 35 | `testLongHesitation` | `pause_long_01` | 我想要…(5s 停顿)…一杯咖啡 | 长时间犹豫后恢复识别 | 包含 `想`, `咖啡` |

### 1.9 特殊测试 (2 个)

| # | 测试方法 | 语料 ID | 说明 | 测试目标 |
|---|---------|---------|------|---------|
| 36 | `testStreamingSimulation` | `zh_short_01` | 以 0.5s chunk 分块推送 "今天天气真好" | 模拟真实流式识别场景 |
| 37 | `testPerformanceBaseline` | `zh_short_01` | Xcode `measure` block 循环 10 轮 | 识别性能基准测量 |

---

## 二、其他测试套件摘要

### 2.1 边界测试 (`QwenASRBoundaryTests`) — 9 个

| 测试方法 | 测试目标 |
|---------|---------|
| `testTinyChunks_160samples` | 10ms 极小 chunk 推送不崩溃 |
| `testNormalChunks_16000samples` | 1s 标准 chunk 推送正常识别 |
| `testSinglePushAllAtOnce` | 一次性推入全部音频 |
| `testVariableChunkSizes` | 变长 chunk (160~32000) 混合推送 |
| `testPureSilenceProducesNoText` | 纯静音无输出 |
| `testTrailingSilenceNoHallucination` | 语音后尾部静音无幻觉 |
| `testGetResultAlwaysReturnsFullText` | getResult 结果单调递增 |
| `testDeltaDropDoesNotLoseText` | delta nil 不丢失已识别文本 |
| `testMemoryGrowthOver5Minutes` | 5 分钟模拟录音内存增长 < 100MB |

### 2.2 并发测试 (`QwenASRConcurrencyTests`) — 4 个

| 测试方法 | 测试目标 |
|---------|---------|
| `testConcurrentPushFromMultipleQueues` | 多队列并发 pushAudio 不崩溃 |
| `testResetDuringActivePush` | 推送过程中 reset 不死锁 |
| `testRecognizerDeinitWhileQueueBusy` | 队列忙碌时释放 recognizer 不崩溃 |
| `testRapidResetCycles` | 快速连续 reset 100 次不泄漏 |

### 2.3 单元测试 (`QwenASRUnitTests`) — 13 个

使用 Mock 识别器，不需要加载真实模型。

| 测试方法 | 测试目标 |
|---------|---------|
| `testInitReturnsNilForNonexistentPath` | 无效路径返回 nil |
| `testInitReturnsNilForEmptyPath` | 空路径返回 nil |
| `testPushAudioForwardsSamples` | pushAudio 正确传递采样数据 |
| `testPushAudioForwardsFinalize` | finalize 标志正确传递 |
| `testGetResultReturnsAccumulatedText` | getResult 返回累积文本 |
| `testGetDeltaReturnsNewText` | getDelta 返回增量文本 |
| `testResetClearsState` | reset 清除识别器状态 |
| `testFlushInjectsSilencePadding` | flush 注入 32000 采样静音 |
| `testFlushSetsFinalize` | flush 设置 finalize 标志 |
| `testNilRecognizerPushReturnsNil` | nil recognizer pushAudio 安全返回 |
| `testNilRecognizerGetResultReturnsEmpty` | nil recognizer getResult 返回空 |
| `testNilRecognizerResetNoOp` | nil recognizer reset 无操作不崩溃 |
| `testAccumulatedTextFallback` | accumulatedText 回退机制 |

---

## 三、测试基础设施

### 匹配模式说明

| 模式 | 说明 |
|------|------|
| `character_error_rate` | 计算 CER (字符错误率) = Levenshtein 距离 / 期望文本长度，需 ≤ 阈值 |
| `contains_all` | 实际输出必须包含所有指定关键词（不区分大小写） |
| `contains` | 实际输出包含期望文本即可 |
| `empty_or_whitespace` | 实际输出为空或仅含空白字符 |

### 文本预处理 (`FuzzyASRMatcher.normalize()`)

CER 计算前会执行归一化：去除中英文标点 → 转小写 → 去除空白。这使得 CER 专注于内容准确性而非标点格式。

### 语料与音频文件

| 文件 | 用途 |
|------|------|
| `tests/fixtures/synthetic_manifest.json` | E2E 语料定义 (~160 条) |
| `tests/fixtures/recorded_manifest.json` | 录制语料定义 (~30 条) |
| `tests/fixtures/audio/synthetic/` | 合成音频 (Edge-TTS + 静音/噪声) |
| `tests/fixtures/audio/recorded/aishell/` | AISHELL-1 真实录音 (需下载) |
| `tests/fixtures/audio/recorded/minds14/` | MINDS-14 对话录音 (需下载) |
| `tests/fixtures/audio/recorded/ascend/` | ASCEND 真实代码切换录音 (需下载) |
| `tests/fixtures/audio/recorded/wenetspeech/` | WenetSpeech 多场景录音 (需下载，gated) |

### 共用 Helper

| 文件 | 用途 |
|------|------|
| `TypelessTests/Helpers/TestEnvironment.swift` | 模型目录 / 语料路径解析 |
| `TypelessTests/Helpers/FuzzyASRMatcher.swift` | 归一化 / CER 计算 / 模糊匹配 |
| `TypelessTests/Helpers/WAVLoader.swift` | WAV 文件加载 |
| `TypelessTests/Helpers/CorpusEntry.swift` | `Corpus` / `CorpusEntry` 数据结构 |
| `TypelessTests/Helpers/MemoryMonitor.swift` | RSS 内存监控 |
| `TypelessTests/Mocks/MockASRStreamRecognizer.swift` | Mock 识别器 (单元测试用) |

---

## 四、运行方式

```bash
# 生成合成语料音频 (Edge-TTS，需联网)
uv run --with edge-tts --with pyyaml python scripts/generate_synthetic_corpus.py

# 仅生成合成音频（静音/噪声，不需要网络）
uv run --with pyyaml python scripts/generate_synthetic_corpus.py --only-synthetic

# macOS say 离线备选（不推荐，发音不自然）
uv run --with pyyaml python scripts/generate_synthetic_corpus.py --say

# 下载录制语料音频 (需联网)
uv run --with 'datasets[audio]' --with soundfile --with scipy \
    python scripts/download_recorded_corpus.py

# 跳过 WenetSpeech（如无 HuggingFace 授权）
uv run --with 'datasets[audio]' --with soundfile --with scipy \
    python scripts/download_recorded_corpus.py --skip-wenetspeech

# 运行全部测试
xcodebuild test -scheme Typeless -destination 'platform=macOS'

# 仅运行 E2E 测试
xcodebuild test -scheme Typeless -only-testing "TypelessTests/QwenASRE2ETests"
```
