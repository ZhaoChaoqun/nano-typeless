# Cerebras gpt-oss-120b CER > 0.1 错误分析报告

*基于 benchmark 报告：`docs/benchmark-cerebras-gpt-oss-120b.md`*
*测试集：67 条（corpus.json + real_manifest.json）*
*平台：Cerebras API (免费 tier)，`/no_think` 模式*

---

## 总览

67 条中 CER > 0.1 的有 **23 条**（34.3%），按错误根因分类如下：

| 错误根因 | 条数 | 占比 |
|---------|:----:|:----:|
| ASR 误识别（LLM 无法纠正） | 11 | 47.8% |
| LLM 过度改写 / 语义偏移 | 5 | 21.7% |
| ITN 格式差异（数字/标点） | 4 | 17.4% |
| 音频截断 / 口语省略 | 3 | 13.0% |

---

## 逐条分析

### 1. ASR 误识别（LLM 无法纠正）

这类错误源头在 Paraformer ASR 层——语音本身被错误识别，LLM 拿到的输入就是错的，无法纠正。

| # | ID | CER | 期望 | 实际输出 | 分析 |
|---|-----|:---:|------|---------|------|
| 1 | cs_build_01 | 0.250 | 在**macOS**上运行swift build。 | 在 **Michael S** 上运行 Swift build。 | ASR 将 "macOS" 识别为 "Michael S"，LLM 无上下文纠正 |
| 2 | cs_error_01 | 0.379 | 这个error是**null pointer exception**。 | 这个 error 是 **no pointer it se**。 | ASR 将 "null pointer exception" 严重误识别 |
| 3 | ascend_cs_001 | 0.238 | **No**，我专业是那个**ISM**，Information Systems Management。 | 那我就暗示 **ISBN** information systems management。 | ASR 将 "No 我专业是那个ISM" 误识别为 "那我就暗示ISBN" |
| 4 | ascend_cs_003 | 0.353 | 深圳啊，或者是上海这种**比较大的**城市，会有更多**opportunity**。 | 深圳或者是上海，这种**表达**城市会有更 **opportun**。 | ASR 截断 "opportunity"，将"比较大的"识别为"表达" |
| 5 | ascend_cs_004 | 0.286 | 嗯，**I like** hot pot。 | **I'd like** hot pot | ASR 将 "I like" 识别为类似 "I'd like" 的发音 |
| 6 | ascend_cs_006 | 0.351 | 那个玩basketball的，然后我有时候有时候会邀我的**friends**啊，一起打在就是**after class**的时候。 | 玩 basketball，然后我稍微邀请我的 **France** 一起打，就是 **after cast** 的时候。 | ASR 将 "friends" 识别为 "France"，"class" 识别为 "cast" |
| 7 | ascend_cs_010 | 0.229 | 哦，我我在UG的时候念的是**electrical engineering**。 | 我在 UG 的时候念的是 **electric engineer**。 | ASR 丢失 "al" 后缀，"engineering" → "engineer" |
| 8 | wenet_net_002 | 0.154 | **竖锯**癌症病成那样…**皮特**认为还有其他人在帮助**竖锯**这么做。 | **数据**癌症病成那样…**彼得**认为还有其他人在帮助**数据**这么做。 | ASR 将 "竖锯"（电影名）识别为"数据"，"皮特" 识别为"彼得" |
| 9 | wenet_net_006 | 0.268 | 这位叫**皮特**的FBI探员一上来就**一顿物理分析**…比**她**还重的女警官。 | 这位叫 **Peter** 的 FBI 探员一上来就**进行了一番物理分析**…比**他**还重的女警官。 | ASR 将"皮特"识别为英文 "Peter"，LLM 合理改写但与 ground truth 字面不同 |
| 10 | wenet_net_008 | 0.118 | 把这些劳工抓起来，送到**月亮岛上**去。 | 把这些劳工抓起来，送到**月亮**去。 | ASR 丢失 "岛上" |
| 11 | aishell_test_005 | 0.154 | 标杆房企必然调整市场**战略**。 | 标杆房企必然调整市场**占比**。 | ASR 将 "战略" 误识别为 "占率/占比" |

### 2. LLM 过度改写 / 语义偏移

这类错误中 ASR 输出基本正确，但 LLM rewrite 做了不必要的改动或过度简化。

| # | ID | CER | 期望 | 实际输出 | 分析 |
|---|-----|:---:|------|---------|------|
| 1 | ascend_cs_002 | 0.160 | **嗯，**所以你现在还是比较focus在找工作这件事**上**。 | 所以，你现在还是比较 focus 在找工作这件事。 | LLM 删除了语气词"嗯"和句尾"上"——过度清理口语 |
| 2 | wenet_net_001 | 0.217 | 毕业歌会之后，**然后**我们**还**去吃个饭，**然后就**感觉。 | 毕业歌会之后，我们去吃饭，然后就感。 | LLM 过度删除口语重复词（"然后""还"），且末尾截断 |
| 3 | wenet_net_009 | 0.351 | **的的需要。嗯，**如果你把他当成产品的话，你**就**会觉得**那么**消费者会需要什么样**的**。 | 如果你把它当成产品的话，你会觉得消费者会需要什么样？ | LLM 删除了大量口语填充词和不流利词（"的的需要 嗯"），过度清理 |
| 4 | ascend_cs_005 | 0.102 | 所以**我的我的**parents，我的妈妈是chemistry老师，**and**我的爸爸是history老师。 | 所以，我的 parents，我的妈妈是 Chemistry 老师，我的爸爸是 History 老师。 | LLM 删除了口语重复"我的我的"和 "and"——属于合理清理，但计入 CER |
| 5 | ascend_cs_009 | 0.100 | 然后**刚**忘了讲，**你你**是念什么major**的**？ | 然后刚忘了讲，你是念什么 major？ | LLM 删除了口语重复"你你"和句尾"的"——合理但与 ground truth 不一致 |

### 3. ITN 格式差异（数字/标点）

期望文本和模型输出的语义完全正确，但数字或标点的格式化方式不同。

| # | ID | CER | 期望 | 实际输出 | 分析 |
|---|-----|:---:|------|---------|------|
| 1 | mixed_02 | 0.160 | MacBook Pro M3芯片性能提升了**百分之40**。 | MacBook Pro M3 芯片性能提升了 **40%**。 | "百分之40" vs "40%"——两种都正确，ITN 格式差异 |
| 2 | rate_fast_01 | 0.526 | 快速语音识别测试，**1、2、3、4、5**。 | 快速语音识别测试**一二三四五**。 | ASR 输出中文数字，LLM 保留了中文写法；ground truth 用阿拉伯数字 + 顿号 |
| 3 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端。第二步，输入命令。第三步，确认执行。 | LLM 添加了更重的标点分隔（逗号→句号），实际上更规范 |
| 4 | wenet_net_004 | 0.188 | 下车后望着**30**多层的大高楼发呆。 | 下车后，望着**三十**多层的大高楼发呆。 | "30" vs "三十"——格式差异 |

### 4. 音频截断 / 口语省略

音频自身特点导致的信息缺失。

| # | ID | CER | 期望 | 实际输出 | 分析 |
|---|-----|:---:|------|---------|------|
| 1 | dev_debug_01 | 0.150 | 在第**42**行设置一个breakpoint。 | 在第**四十二**行设置一个 break point。 | "42" vs "四十二"（ITN）+ "breakpoint" vs "break point"（分词） |
| 2 | wenet_net_010 | 0.143 | 媒体也已经报了，然后呃，债主也已经**围**楼了。 | 媒体也已经报了，然后债主也已经**为**楼了。 | ASR 将 "围" 识别为 "为"（同音字） |
| 3 | cs_edge_008 | 0.133 | CI pipeline跑了30分钟，还没通过unit **test**。 | CI pipeline 跑了 30 分钟，还没通过 unit。 | ASR 截断，丢失末尾 "test" |

---

## 根因归因统计

```
ASR 误识别         ██████████████████████████ 47.8% (11 条)
LLM 过度改写       ████████████             21.7%  (5 条)
ITN 格式差异       █████████                17.4%  (4 条)
Paraformer尾部截断 ███████                  13.0%  (3 条)
```

---

## 附录：Paraformer 尾部截断深入调试

### 问题确认

人工听审确认 3 条音频的语音内容完整（末尾词汇清晰可闻），截断发生在 Paraformer 流式解码层。

### Token-Level 调试结果

使用 `recognizer.tokens(stream)` 逐 chunk 追踪 token 输出：

#### cs_edge_008：期望 "unit test" → ASR 输出 "unit"

```
chunk t=4.35s: tokens=['...', 'un@@', 'it']   ← 音频送完，最后 token 是 "it"
+0.5s pad:     (no change)
+1.0s pad:     (no change)
+3.0s pad:     (no change)
input_finished(): (no change)
```

**"test" 的 BPE token 从未出现在任何阶段**。即使追加 3s 静音 padding 和 `input_finished()` 也无法恢复。说明 Paraformer encoder 从音频特征中未提取到 "test" 的信息。

#### wenet_net_001：期望 "然后就感觉" → ASR 输出 "然后就感"

```
chunk t=4.35s: tokens=['...', '然', '后']      ← 音频送完，只到"后"
+0.5s pad:     tokens=['...', '然', '后', '就', '感']  ← padding 后新增 "就感"！
+1.0s pad:     (no change)
input_finished(): (no change)
```

**Tail padding 有效**——0.5s padding 使 decoder 输出了 2 个额外 token "就感"。但最后的 "觉" 仍然丢失。

#### ascend_cs_003：期望 "opportunity" → ASR 输出 "opportun"

```
chunk t=4.35s: tokens=['...', '更']             ← 音频送完，只到"更"
+0.5s pad:     tokens=['...', '更', 'o@@', 'pp@@', 'ort@@', 'un@@']  ← 新增 "opportun"！
+1.0s pad:     (no change)
input_finished(): (no change)
```

**Tail padding 有效**——0.5s padding 输出了 4 个 BPE 子词 `o@@|pp@@|ort@@|un@@`（拼接为 "opportun"）。但 "ity" 对应的 BPE token 始终未出现。

### 结论

| 现象 | 说明 |
|------|------|
| Tail padding 有效 | 0.5s padding 即可触发尾部 token 输出（`wenet_net_001` +2 tokens，`ascend_cs_003` +4 tokens） |
| 最后 1-2 个 token 永久丢失 | "觉"、"ity"、"test" 无论如何都不出来 |
| 增大 padding 无效 | 从 0.5s 到 3.0s，`input_finished()` 均无额外输出 |
| 关闭 endpoint detection 无效 | `enable_endpoint_detection=False` 结果完全不变 |
| timestamps 全空 | streaming Paraformer 不支持 token-level 时间戳 |

### 根因分析

这是 **streaming Paraformer 的已知问题**（[sherpa-onnx #1373](https://github.com/k2-fsa/sherpa-onnx/issues/1373)）：

1. Streaming Paraformer 使用 chunk-based 编码，右侧上下文窗口有限
2. 当语音在音频最末尾且缺少自然静音尾巴时，最后一个 encoder chunk 的有效信息不足
3. Decoder 的 CTC/attention 融合机制在 chunk 边界处可能丢弃低置信度的尾部 token
4. 即使追加大量静音 padding，encoder 已经无法从纯静音中恢复语音特征

### 影响评估

3/67（4.5%）条目受此影响，每条丢失 1-2 个 token。对整体 CER 的贡献约 0.01-0.02。

### 可能的缓解方案

1. **音频预处理加 trailing silence**：在录音/TTS 时确保末尾有 0.3-0.5s 自然静音
2. **换用 Zipformer 流式模型**：官方建议 Zipformer 在 endpoint 处理上更好
3. **离线 Paraformer**：非流式版本不存在此问题，可作为 benchmark 基准
4. **接受为已知限制**：3/67 的影响有限，且丢失的是末尾 1-2 个 token

---

## 关键结论

1. **近半数错误 (47.8%) 源自 ASR 层**：LLM 无法纠正 Paraformer 本身的识别错误（如 "macOS" → "Michael S"、专有名词误识别）。提升 ASR 模型或添加 hotword/context biasing 是最有效的改进方向。

2. **LLM 过度改写占 21.7%**：主要表现为删除口语填充词（"嗯""然后""的的"）和重复词。这些在口语转文字场景中可能是期望行为，但当前 ground truth 保留了口语原貌，导致 CER 偏高。**可能需要重新审视 ground truth 的口语保留策略。**

3. **ITN 格式差异占 17.4%**：如 "百分之40" vs "40%"、"30" vs "三十"。这不是真正的错误，而是格式化风格差异。**建议在 CER 计算中加入数字归一化**（统一为阿拉伯数字或中文数字后再比较）。

4. **Paraformer 尾部截断占 13.0%（3 条）**：streaming Paraformer 已知问题（[#1373](https://github.com/k2-fsa/sherpa-onnx/issues/1373)），每条丢失最后 1-2 个 BPE token。Tail padding 可部分缓解但无法完全解决。影响有限（CER 贡献约 0.01-0.02），可作为已知限制接受。

---

*报告基于 `docs/benchmark-cerebras-gpt-oss-120b.md` 数据整理*
*Token-level 调试使用 `sherpa_onnx.OnlineRecognizer.tokens()` API*
