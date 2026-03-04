# Qwen3-ASR 流式识别四大配置参数详解

## 概览

| 参数 | C API 函数 | 默认值 | 控制目标 |
|------|-----------|--------|---------|
| `chunk_sec` | `qwen_asr_stream_set_chunk_sec` | **2.0** 秒 | 每次送入解码器的音频窗口大小 |
| `rollback` | `qwen_asr_stream_set_rollback` | **5** tokens | 每个 chunk 末尾保留多少 token 不输出（等待确认） |
| `unfixed_chunks` | `qwen_asr_stream_set_unfixed_chunks` | **2** chunks | 前几个 chunk 完全不输出（冷启动） |
| `max_new_tokens` | `qwen_asr_stream_set_max_new_tokens` | **32** tokens | 单个 chunk 最多生成多少新 token |

这四个参数共同控制了流式 ASR 中 **延迟 vs 准确性** 的平衡。

---

## 前置知识：自回归 vs 非自回归

在理解四个参数之前，需要先理解 Qwen3-ASR 的解码方式——**自回归（Autoregressive）**。

### 什么是自回归？

自回归的含义是：**每个输出都依赖前面已经生成的输出**。模型一次只生成一个 token，然后把这个 token 加入上下文，再生成下一个。

用一个日常类比：

> 自回归就像**手写一行字**——你必须先写完第 1 个字，才知道第 2 个字写在哪里、写什么。
> 每一笔的位置和内容都取决于前面已经写好的部分。

### 自回归解码过程

Qwen3-ASR 的 Decoder 就是这样工作的（对应 `transcribe.rs:669-678`）：

```
input: "今天天气真不错"

            +-- Encoder ------+
audio PCM ->| feature extract |-> encoder output
            +-----------------+
                    |
                    v
            +-- Decoder (AR) --+
step 1: [enc_out]               -> "今"
step 2: [enc_out] + [今]        -> "天"
step 3: [enc_out] + [今,天]     -> "天"
step 4: [enc_out] + [今,天,天]  -> "气"
step 5: ...                     -> "真"
step 6: ...                     -> "不"
step 7: ...                     -> "错"
step 8: ...                     -> [EOS]
            +-------------------+
```

每个 step 需要一次完整的 Decoder forward pass（约 15-25ms），所以：
- 生成 7 个 token 需要 7 次 forward → 约 100-175ms
- 这就是 `max_new_tokens` 参数的意义——限制最大 step 数

### 非自回归是什么？

非自回归（Non-Autoregressive, NAR）模型可以**一次性并行生成所有输出**：

```
自回归 (AR):
  step 1 → "今"
  step 2 → "天"  (需要等 step 1 完成)
  step 3 → "天"  (需要等 step 2 完成)
  ...串行，共 7 步

非自回归 (NAR):
  一步  → "今天天气真不错"  (所有 token 并行生成)
  只需 1 步！
```

### 对比

|  | 自回归 (AR) | 非自回归 (NAR) |
|---|---|---|
| **生成方式** | 逐 token 串行 | 所有 token 并行 |
| **速度** | 慢（N 个 token = N 步） | 快（1 步） |
| **质量** | 高（每步参考前文） | 较低（缺乏前后依赖） |
| **代表模型** | Qwen3-ASR, Whisper | Paraformer, FastSpeech |
| **能否流式** | 天然适合流式输出 | 需要额外设计 |
| **需要 rollback** | 是（边界处不确定） | 通常不需要 |

### 为什么 Qwen3-ASR 用自回归？

1. **质量更高** — 每个 token 都能参考前面的输出，上下文连贯
2. **灵活** — 输出长度不固定，模型自己决定何时停止
3. **与 LLM 架构统一** — Qwen3-ASR 的 Decoder 就是 Qwen3 语言模型，共享权重

代价就是速度较慢，所以需要 `max_new_tokens` 来限制、需要 `rollback` 来处理不确定的边界。

### 与四个参数的关系

| 自回归特性 | 导致的问题 | 对应参数 |
|---|---|---|
| 逐 token 串行生成 | 每 chunk 解码耗时 | `max_new_tokens`（限制步数） |
| 后续输入可能改变早期判断 | chunk 边界处 token 不稳 | `rollback`（延迟输出等确认） |
| 首个 chunk 上下文不足 | 初始预测不准确 | `unfixed_chunks`（冷启动保护） |
| 需要攒够音频才能解码 | 触发解码的时机 | `chunk_sec`（分块大小） |

> **Typeless 项目中的另外两个 ASR 引擎——SenseVoice 和 Paraformer——都是非自回归模型。**
> 它们不需要 rollback 机制，一次编码直接出结果，所以延迟更低但灵活性不如 Qwen3-ASR。

---

## 1. `chunk_sec` — 音频分块大小

### 作用

控制每次推送到解码器的音频时长。音频流被切分为固定大小的 chunk，每个 chunk 独立编码后送入 decoder 做自回归解码。

### 代码位置

```
context.rs:53     → pub stream_chunk_sec: f32,     // 字段定义
context.rs:146    → stream_chunk_sec: 2.0,          // 默认值
transcribe.rs:904 → let chunk_samples = (ctx.stream_chunk_sec * SAMPLE_RATE as f32) as usize;
```

`SAMPLE_RATE = 16000`，所以默认 `chunk_samples = 32000`（即 2 秒的 16kHz PCM）。

### 工作原理示意

```
音频流（用户持续说话）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━→ 时间
|← chunk 0 →|← chunk 1 →|← chunk 2 →|← chunk 3 →|
    2.0s         2.0s         2.0s         2.0s

每攒够一个 chunk 的音频，触发一次完整的 "编码 + 解码" 流程：

chunk 0 到达 → [Encoder] → [Decoder] → 生成 tokens → (不输出，冷启动)
chunk 1 到达 → [Encoder] → [Decoder] → 生成 tokens → (不输出，冷启动)
chunk 2 到达 → [Encoder] → [Decoder] → 生成 tokens → 输出部分确认的文字
chunk 3 到达 → [Encoder] → [Decoder] → 生成 tokens → 输出新增确认的文字
...
```

### 参数影响

| chunk_sec | 效果 |
|-----------|------|
| **减小**（如 1.0s） | 更快触发解码，首字延迟低；但每次可用上下文少，准确率可能下降 |
| **增大**（如 4.0s） | 每次有更多上下文可用，准确率高；但用户要等更久才看到文字 |

### 推荐范围

`1.0 ~ 3.0` 秒。对于实时对话场景，`1.5 ~ 2.0` 是较好的平衡点。

---

## 2. `rollback` — 回滚窗口

### 作用

这是流式 ASR 最核心的机制。每次 decoder 生成新 token 后，**末尾 N 个 token 不立即输出**，而是保留到下一个 chunk 到来时重新确认。这是因为 ASR 模型在 chunk 边界处的预测不一定准确——后续音频可能改变对当前末尾 token 的判断。

### 代码位置

```
context.rs:54      → pub stream_rollback: i32,       // 字段定义
context.rs:147     → stream_rollback: 5,              // 默认值
transcribe.rs:1025 → (state.raw_tokens.len() as i32 - rollback).max(0) as usize  // prefix 计算
transcribe.rs:1263 → (n_text_tokens as i32 - rollback).max(0) as usize           // 输出边界
```

### 图解回滚机制

假设 `rollback = 3`，以用户说 "今天天气真不错" 为例：

```
Chunk 2 decode:  [今][天] [天][气][真]
                  -------- -----------
                  确认区    回滚区(3)
                  输出"今天" 保留不输出

Chunk 3 decode:  [今][天] [天][气][真][不][错]
                  --------------- -----------
                  确认区           回滚区(3)
                  新增输出"天气"    保留不输出

Finalize:        [今][天] [天][气][真][不][错]
                  --------------------------------
                  全部输出
                  新增输出"真不错"
```

### 为什么需要回滚？

没有回滚时，chunk 边界处容易出现 "幻觉" tokens：

```
无回滚（rollback=0）:
  chunk 2 解码: "今天天气真好" → 立即输出 "今天天气真好"
  chunk 3 解码: "今天天气真不错" → 但 "好" 已经输出了！无法撤回

有回滚（rollback=3）:
  chunk 2 解码: "今天天气真好" → 输出 "今天天"，保留 "气真好"
  chunk 3 解码: "今天天气真不错" → 重新确认，输出 "气真"，保留 "不错"
                                   → 模型自我纠正了 "好" → "不错"
```

### 关键实现：token 被分为三部分

```
raw_tokens (某次解码完整结果):

  [ASR_TEXT] [今][天][天][气] [真][不][错]
             |--- 7 个 text tokens ---|

  candidate_len = 7 - rollback(3) = 4
  (即只确认前 4 个)

  [今][天][天][气]    [真][不][错]
  ----------------    ------------
  确认并输出            回滚区(保留)

下一次解码时，回滚区的 token 作为 "prefix tokens" 被喂回 decoder:
  prefix_tokens = raw_tokens[0..len-rollback]  ->  喂回作为上下文
```

### 参数影响

| rollback | 效果 |
|----------|------|
| **0** | 零延迟，但边界处可能输出错误 token（无法撤回） |
| **3** | 低延迟，轻微保护 |
| **5**（默认） | 中等延迟，良好的纠错能力 |
| **10** | 高延迟，很强的纠错能力；但用户感知延迟大 |

### 延迟计算

回滚带来的额外延迟 ≈ `rollback × chunk_sec / avg_tokens_per_chunk`

以默认值为例（每 chunk 约产生 10-20 tokens，rollback=5）：
- 约有 1/3 的 token 被缓冲，对应约 0.5-1.0 秒额外延迟

---

## 3. `unfixed_chunks` — 冷启动窗口

### 作用

前 N 个 chunk 完全不输出任何文字。原因：模型刚开始处理音频时，可用上下文太少，预测不稳定。等积累了足够音频后再开始输出，能显著提升首次输出的准确性。

### 代码位置

```
context.rs:55      → pub stream_unfixed_chunks: i32,   // 字段定义
context.rs:148     → stream_unfixed_chunks: 2,          // 默认值
transcribe.rs:1021 → if ctx.past_text_conditioning
                        && state.chunk_idx >= unfixed_chunks  // 是否开始 prefix
transcribe.rs:1262 → } else if state.chunk_idx >= unfixed_chunks {
                        (n_text_tokens as i32 - rollback).max(0) as usize  // 才开始输出
                     } else {
                        0  // 不输出
                     };
```

### 图解冷启动

```
unfixed_chunks = 2, chunk_sec = 2.0s:

时间线:  0s      2s      4s      6s      8s
         |       |       |       |       |
chunk:   [  0  ] [  1  ] [  2  ] [  3  ] [  4  ]
         冷启动   冷启动    ↑首次输出
                          |
                          +→ 从 chunk 2 开始，已积累 4 秒音频
                             模型可以回顾前 4 秒做更准确的判断

chunk 0 (0-2s):  解码 → "今天" → candidate_len = 0 → 不输出
chunk 1 (0-4s):  解码 → "今天天气" → candidate_len = 0 → 不输出
chunk 2 (0-6s):  解码 → "今天天气真不错" → candidate_len = 7-5=2 → 输出 "今天"
chunk 3 (0-8s):  解码 → "今天天气真不错啊" → candidate_len = 8-5=3 → 新增输出 "天"
```

### 与 rollback 的配合

两个参数同时影响首次输出时间：

```
首次输出时间 = unfixed_chunks × chunk_sec + rollback_delay

默认值:  2 × 2.0s + ~1.0s ≈ 5 秒后首次看到文字

降低延迟方案:
  unfixed_chunks=1, chunk_sec=1.5 → 1.5s + ~0.5s ≈ 2 秒后首次看到文字
```

### 参数影响

| unfixed_chunks | 效果 |
|----------------|------|
| **0** | 立即开始输出，但前几个 token 可能不准 |
| **1** | 等 1 个 chunk（默认 2s），轻微保护 |
| **2**（默认） | 等 2 个 chunk（默认 4s），首次输出较准确 |
| **3+** | 更久的等待，适合要求极高准确率的场景 |

---

## 4. `max_new_tokens` — 单 chunk 最大 token 数

### 作用

限制每个 chunk 解码时，decoder 最多新生成多少 token。这是一个安全阀——防止 decoder 在某个 chunk 上 "跑飞"（无限生成、幻觉循环等）。

### 代码位置

```
context.rs:56      → pub stream_max_new_tokens: i32,   // 字段定义
context.rs:149     → stream_max_new_tokens: 32,         // 默认值
transcribe.rs:907  → let max_new_tokens = if ctx.stream_max_new_tokens > 0
                        { ctx.stream_max_new_tokens } else { 32 };
transcribe.rs:1136 → while n_generated < max_new_tokens {  // 解码循环上限
                        if token == TOKEN_ENDOFTEXT || TOKEN_IM_END { break; }
                        chunk_tokens.push(token);
                        ...
                     }
```

### 图解 token 上限

```
正常情况 (2s chunk 通常产生 10-20 tokens):

  chunk 音频: "今天天气真不错" → decoder 生成 7 tokens → 正常，远低于上限 32

异常情况（无此限制时可能发生）:

  chunk 音频: [一段噪音] → decoder 产生幻觉:
    "的的的的的的的的的的的的的的的的的的的的的的..." → 无限循环！

  有 max_new_tokens=32 保护:
    "的的的的..." → 到第 32 个 token 时强制停止
    + degeneracy detection（退化检测）会发现重复并重置状态
```

### 与解码时间的关系

```
每 chunk 解码时间 ≈ max_new_tokens × per_token_ms

  per_token_ms ≈ 15-25ms (Apple M1/M2)

  max_new_tokens=32:  最多 32 × 20ms = 640ms 解码时间
  max_new_tokens=16:  最多 16 × 20ms = 320ms 解码时间
  max_new_tokens=64:  最多 64 × 20ms = 1280ms 解码时间
```

### 参数影响

| max_new_tokens | 效果 |
|----------------|------|
| **16** | 每 chunk 解码快，但长语句可能被截断（需要更多 chunk 才能完成） |
| **32**（默认） | 适合 2 秒 chunk，正常语速 2 秒≈10-15 个中文字（对应 10-20 tokens） |
| **64** | 适合更大的 chunk_sec（如 4s），避免截断 |
| **过大**（如 256） | 幻觉/退化时会浪费大量计算时间 |

### 经验公式

```
推荐 max_new_tokens ≈ chunk_sec × 15 (中文)
推荐 max_new_tokens ≈ chunk_sec × 20 (英文，token 更碎)

chunk_sec=1.5 → max_new_tokens ≈ 22-30
chunk_sec=2.0 → max_new_tokens ≈ 30-40 (默认 32 合适)
chunk_sec=3.0 → max_new_tokens ≈ 45-60
```

---

## 四参数协同工作全景图

```
用户说话: "我想订一张明天从北京到上海的机票"

时间线:  0s    1s    2s    3s    4s    5s    6s    7s    8s
音频:    ════════════════════════════════════════════════════════

         ┌─ chunk_sec=2.0 ─┐
chunk 0: [我想订一张明天从北]        (0-2s)
chunk 1: [我想订一张明天从北京到上海]  (0-4s, 累积)
chunk 2: [我想订一张明天从北京到上海的机票] (0-6s, 累积)

═══════════════════════════════════════════════════════════════
chunk 0 (t=2s):
  decoder 生成 raw_tokens: [我][想][订][一][张]
  unfixed_chunks=2 → chunk_idx=0 < 2 → candidate_len = 0
  输出: (无)                                              ← 冷启动期

chunk 1 (t=4s):
  decoder 生成 raw_tokens: [我][想][订][一][张][明][天][从][北][京]
  unfixed_chunks=2 → chunk_idx=1 < 2 → candidate_len = 0
  输出: (无)                                              ← 冷启动期

chunk 2 (t=6s):
  decoder 生成 raw_tokens: [我][想][订][一][张][明][天][从][北][京][到][上][海]
  chunk_idx=2 >= 2 → 开始输出
  n_text_tokens = 13
  candidate_len = 13 - rollback(5) = 8
  输出: "我想订一张明天从"                                  ← 首次输出 8 tokens
  回滚区保留: [北][京][到][上][海]

chunk 3 (t=8s):
  decoder 生成 raw_tokens: [我][想][订][一][张][明][天][从][北][京][到][上][海][的][机][票]
  n_text_tokens = 16
  candidate_len = 16 - 5 = 11
  已输出 8，新增输出: "北京到"                              ← 增量输出 3 tokens
  回滚区保留: [上][海][的][机][票]

finalize (用户停止说话):
  candidate_len = n_text_tokens (全部)
  新增输出: "上海的机票"                                   ← 刷出回滚区全部
═══════════════════════════════════════════════════════════════

最终用户看到的输出时间线:
  t=0s~5s:  (等待中，屏幕无文字)
  t=6s:     "我想订一张明天从"        ← 首次输出
  t=8s:     "我想订一张明天从北京到"    ← 增量更新
  t=finalize: "我想订一张明天从北京到上海的机票" ← 完整结果
```

---

## 退化检测（补充知识）

除了上述 4 个可配置参数，流式引擎还有内置的退化检测机制，使用硬编码常量：

```rust
const STREAM_DEGEN_MAX_PERIOD: usize = 6;     // 检测重复 pattern 的最大周期
const STREAM_DEGEN_MIN_REPEATS: usize = 4;    // 重复 4 次触发退化
const STREAM_STALE_CHUNKS: i32 = 4;           // 连续 4 个 chunk 结果不变触发退化
const STREAM_RESET_INTERVAL_CHUNKS: i32 = 45; // 每 45 chunk 强制 re-anchor
const STREAM_RESET_CARRY_TOKENS: usize = 24;  // 重置时保留最后 24 个 stable token
```

退化检测流程：
```
每个 chunk 解码后检查 raw_tokens:

1. 停滞检测: raw_tokens 是否与上次完全相同？
   → 连续 4 次 (STREAM_STALE_CHUNKS) 相同 → 退化

2. 重复检测: 末尾是否有重复 pattern？
   例如: [...][的][的][的][的][的][的]
   → stream_tail_repeat_blocks() 检测到周期=1, 重复=6 次
   → 6 >= 4 (STREAM_DEGEN_MIN_REPEATS) → 退化

3. 退化处理: 清空 raw_tokens，仅保留最后 24 个 stable tokens 作为上下文
   → 相当于 decoder 从近处重新开始，避免幻觉扩散
```

---

## 当前 Typeless 项目中的调用情况

在 `QwenASRRecognizer.swift` 中，这 4 个配置函数**均未被调用**，使用的全部是默认值：

| 参数 | 当前值（默认） | 建议值（实时对话场景） |
|------|--------------|---------------------|
| `chunk_sec` | 2.0s | 1.5s |
| `rollback` | 5 | 3~5 |
| `unfixed_chunks` | 2 | 1 |
| `max_new_tokens` | 32 | 24 |

### 对首字延迟的影响

```
当前默认:    unfixed_chunks(2) × chunk_sec(2.0) = 4.0s 冷启动 + rollback 延迟 ≈ 5s
推荐调整后:  unfixed_chunks(1) × chunk_sec(1.5) = 1.5s 冷启动 + rollback 延迟 ≈ 2.5s
```

首字延迟可从约 5 秒降低到约 2.5 秒。

---

## 参数调优决策树

```
你的场景是什么？
│
├─ 实时对话/会议记录（低延迟优先）
│   → chunk_sec=1.5, rollback=3, unfixed_chunks=1, max_new_tokens=24
│   → 首字延迟 ~2s，可能偶尔出现 1-2 字的修正
│
├─ 语音输入法（平衡方案）
│   → chunk_sec=2.0, rollback=5, unfixed_chunks=2, max_new_tokens=32
│   → 首字延迟 ~5s，输出稳定性好（当前默认值）
│
├─ 字幕/离线处理（准确率优先）
│   → chunk_sec=3.0, rollback=8, unfixed_chunks=3, max_new_tokens=48
│   → 首字延迟 ~10s，极高稳定性
│
└─ 超低延迟演示（牺牲准确性）
    → chunk_sec=1.0, rollback=2, unfixed_chunks=0, max_new_tokens=16
    → 首字延迟 ~1s，但可能频繁出现需要修正的 token
```

---

## 附录：PCM 与 16kHz 采样率

文档中多次出现的 "16kHz PCM" 是 ASR 系统最基础的音频格式要求，以下做详细解释。

### PCM 是什么？

**PCM（Pulse Code Modulation，脉冲编码调制）** 是数字音频最原始的表示方式——直接记录声波的采样值，不做任何压缩。

```
声音是空气振动产生的连续波形（模拟信号）：

         ╱╲      ╱╲
        ╱  ╲    ╱  ╲
───────╱────╲──╱────╲──────  ← 连续的空气压力变化
              ╲╱

PCM 的做法：每隔固定时间，测量一次波形的高度（电压值），记录为一个数字：

         ╱╲      ╱╲
        ╱  ╲    ╱  ╲
───•───╱•───╲•─╱•───╲•────  ← 在固定间隔处采样
   │   │ │   │ │ │   │ │
   ↓   ↓ ↓   ↓ ↓ ↓   ↓ ↓
  [0] [0.3][0.7][0.9][0.7][0.3][0][-0.3]...  ← PCM 数据：一串浮点数
```

每个采样点就是一个 float 数值，范围通常是 [-1.0, 1.0]。

### 常见音频格式与 PCM 的关系

| 层级 | 格式 | 说明 |
|------|------|------|
| **原始** | PCM | 原始采样值，无压缩 |
| **无压缩封装** | WAV | PCM + 44 字节文件头（采样率、位深等元信息） |
| **有损压缩** | MP3 | PCM → 频域变换 → 心理声学模型 → 压缩（约 1/10 体积） |
| | AAC | 类似 MP3 但效率更高（iPhone 默认录音格式） |
| | Opus | 低延迟有损压缩（微信语音、WebRTC 使用） |

ASR 模型需要的是最原始的 PCM 数据。如果输入是 MP3/AAC，需要先解码回 PCM。

### 为什么是 16kHz？

采样率（Sample Rate）表示每秒采样多少次。16kHz 意味着每秒 16,000 个采样点。

**根据奈奎斯特采样定理：采样率必须至少是信号最高频率的 2 倍，才能完整还原信号。**

```
16kHz 采样率 → 能表示的最高频率 = 16000 / 2 = 8000 Hz (8kHz)
```

人类语音的频率分布：

```
频率 (Hz):   0    500   1k    2k    3k    4k    5k    6k    7k    8k
             |─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────|
语音基频:    ████████████                                    男性 85-180Hz
                   ████████████                              女性 165-255Hz
语音共振峰:  ████████████████████████████████                 核心语义信息
辅音高频:                          ██████████████████████     s, f, th 等
                                                        ↑
                                                   8kHz 截止频率
                                                   (16kHz采样的上限)
```

| 采样率 | 可表示频率 | 适用场景 | 每秒数据量 (f32) |
|--------|----------|---------|-----------------|
| 8 kHz | 0-4 kHz | 电话语音（勉强够用） | 32 KB/s |
| **16 kHz** | **0-8 kHz** | **语音识别标准**（覆盖全部语音频段） | **64 KB/s** |
| 22.05 kHz | 0-11 kHz | AM 广播 | 88 KB/s |
| 44.1 kHz | 0-22 kHz | CD 音质（覆盖全部人耳范围） | 176 KB/s |
| 48 kHz | 0-24 kHz | 专业音频/视频 | 192 KB/s |

16kHz 是 ASR 领域的事实标准，原因：
- **8kHz 不够**：丢失 s/f/th 等辅音的高频信息，识别率下降
- **44.1kHz 浪费**：8kHz 以上的频率对语音识别几乎无贡献，但数据量翻倍，计算量也翻倍
- **16kHz 刚好**：完整覆盖语音全频段，数据量最经济

几乎所有主流 ASR 模型都使用 16kHz：Whisper、Qwen3-ASR、Paraformer、SenseVoice 等。

### Qwen3-ASR 中的具体体现

```
SAMPLE_RATE = 16000  (定义在 config.rs 中)

1 秒音频 = 16000 个 f32 采样点 = 64 KB

chunk_sec = 2.0 → chunk_samples = 2.0 × 16000 = 32000 个采样点 = 128 KB

每个采样点是一个 f32（4 字节），值域 [-1.0, 1.0]：
  -1.0 ← 波形最低点
   0.0 ← 静默
  +1.0 ← 波形最高点
```

### 在 Typeless 中的音频流

```
macOS 麦克风 → Core Audio (通常 48kHz)
                    │
                    ↓ 重采样 (resample)
              16kHz PCM f32 mono
                    │
                    ↓ 4096 samples 一个 buffer (≈ 0.256 秒)
              RecordingManager.swift
                    │
                    ↓ 喂入 ASR 引擎
              qwen_asr_stream_push(engine, stream, samples, n_samples, finalize)
```

macOS 麦克风默认采集 48kHz，Typeless 在 `RecordingManager.swift` 中将其重采样为 16kHz 后再送入 ASR 引擎。

### mono（单声道）是什么意思？

```
立体声 (stereo):    左声道 [L1, L2, L3, ...]
                    右声道 [R1, R2, R3, ...]
                    → 两路数据，每秒 32000 个采样点

单声道 (mono):      [S1, S2, S3, ...]
                    → 一路数据，每秒 16000 个采样点

语音识别只需要单声道——人说话的内容不分左右。
立体声输入时，通常取两路平均: S = (L + R) / 2
```

---

## 附录：Mel Spectrogram（梅尔频谱图）

Qwen3-ASR 的 encoder 输入不是原始 PCM，而是从 PCM 计算出的 **mel spectrogram**。这是所有现代 ASR 模型（Whisper、Qwen3-ASR、Paraformer、SenseVoice）共用的音频前端表示。

### 为什么不直接用 PCM？

PCM 是时域信号——每个采样点表示某一瞬间的气压值。但人耳和大脑处理声音靠的是**频率**，不是瞬时气压。

```
PCM 波形（时域）：
   +1 ┤     ╱╲      ╱╲
      │    ╱  ╲    ╱  ╲         ← 看不出"这是什么声音"
   0  ├───╱────╲──╱────╲───
      │         ╲╱
   -1 ┤

Mel Spectrogram（频域+时域）：
      │ ██                       ← 低频能量强（元音共振峰）
  频率 │ ░░██                     ← 中频
      │ ░░░░░░██                 ← 高频能量弱
      └────────────→ 时间         ← 每列就是一帧，能看出"哪个频率在哪个时刻响"
```

语音的本质信息（元音/辅音区分、声调、语义）藏在**频率分布随时间的变化**中，而不是原始波形的形状中。

### 三步计算过程

Mel spectrogram 的计算分三步，对应 `audio.rs:273` 的 `mel_spectrogram()` 函数：

```
原始 PCM                   STFT                    Mel 滤波 + 取对数
 (时域)          ──→      (频域)          ──→      (Mel 频域)
                      分帧 + 加窗 + FFT         三角滤波器组 + log

[16000 个采样/秒]     [201 频率 × N 帧]        [128 mel bins × N 帧]
```

#### Step 1: 分帧 + 加窗

把连续的 PCM 信号切成一段段重叠的"帧"：

```
PCM 信号:  ════════════════════════════════════════════════════
           |← 帧0 (400点) →|
                    |← 帧1 (400点) →|
                             |← 帧2 (400点) →|
                                      |← 帧3 →|
           |←160→|←160→|←160→|
            hop    hop    hop

窗口大小 (WINDOW_SIZE) = 400 采样 = 25ms
步进大小 (HOP_LENGTH)  = 160 采样 = 10ms
重叠长度 = 400 - 160 = 240 采样 = 15ms (60% 重叠)
```

每帧乘以 **Hann 窗函数**（两端平滑衰减为零），避免帧边界处的频谱泄漏：

```
Hann 窗:
  1.0 ┤      ╱──╲
      │     ╱    ╲
  0.5 ┤    ╱      ╲
      │   ╱        ╲
  0.0 ├──╱──────────╲──
      0             400
```

#### Step 2: FFT → 功率谱

对每帧加窗后的 400 个采样做**离散傅里叶变换（DFT/FFT）**，得到 201 个频率分量（`N_FFT/2 + 1 = 201`）的功率：

```
一帧 PCM (400 点):
  [0.1, -0.3, 0.5, 0.7, ...]  ← 时域：看不出频率信息

       ↓ FFT

功率谱 (201 点):
  频率:    0Hz    80Hz   160Hz   ...   4kHz   ...   8kHz
  功率:    0.01   0.15   0.82    ...   0.03   ...   0.001
                         ↑
                    这个频率最强 → 说明当前帧有 160Hz 的声音成分
```

每个频率 bin 的间隔 = 采样率 / N_FFT = 16000 / 400 = **40 Hz**。

#### Step 3: Mel 滤波 + 取对数

将 201 个线性频率 bin 通过 **128 个三角形 Mel 滤波器**映射为 128 个 Mel bin：

```
线性频率轴 (Hz):
  0    500    1k    2k    3k    4k    5k    6k    7k    8k
  |───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───|

Mel 滤波器组（128 个三角滤波器）：
  低频段: ╱╲ ╱╲ ╱╲ ╱╲ ╱╲ ╱╲            ← 窄，频率分辨率高
  高频段:          ╱──╲  ╱────╲  ╱──────╲  ← 宽，频率分辨率低
```

**为什么用 Mel 尺度？** 人耳对低频的分辨能力远高于高频——你能轻松区分 200Hz 和 300Hz，但很难区分 7000Hz 和 7100Hz。Mel 尺度模拟了这种非线性感知：

```
Mel 尺度 vs 线性频率:

  Mel │ 3000 ┤                      ╱
      │      │                   ╱╱
      │ 2000 ┤              ╱╱╱
      │      │          ╱╱╱
      │ 1000 ┤     ╱╱╱╱
      │      │ ╱╱╱╱
      │    0 ├╱──────┼──────┼──────┼
             0     2000    4000    8000  Hz

  低频段：100Hz 的差异 ≈ 大量 Mel 值变化 → 分配更多滤波器
  高频段：100Hz 的差异 ≈ 很小 Mel 值变化 → 分配更少滤波器
```

最后取 **log**（对数），因为人耳感知到的"响度"与能量的对数成正比（10 倍能量 ≈ 感知到的 2 倍响度）：

```
mel_value = log(max(mel_filtered_power, 1e-10))
```

### Qwen3-ASR 的具体参数

| 参数 | 值 | 定义位置 | 含义 |
|------|-----|---------|------|
| `MEL_BINS` | 128 | `config.rs:4` | Mel 滤波器数量（输出维度） |
| `N_FFT` | 400 | `audio.rs:6` | FFT 窗口大小（400 采样 = 25ms） |
| `WINDOW_SIZE` | 400 | `config.rs:5` | Hann 窗大小 |
| `HOP_LENGTH` | 160 | `config.rs:5` | 帧步进（160 采样 = 10ms） |

对应关系：**1 帧 = 10ms 音频**，每帧产生一个 128 维向量。

### 帧数计算

```
n_frames = (n_samples + padding - N_FFT) / HOP_LENGTH + 1

例：2 秒音频 (32000 采样):
  n_frames ≈ 32000 / 160 = 200 帧

输出 shape: [128, 200]  → 128 个 Mel bin × 200 帧
  = 25600 个 f32 值 ≈ 100 KB
```

### 与 Encoder 的连接

```
PCM 音频 (16kHz, f32)
       ↓ mel_spectrogram()
Mel Spectrogram [128 × n_frames]      ← 每 10ms 一帧，128 维
       ↓ Encoder (audio tower)
       ↓  3 层卷积: stride ≈ 4x 下采样
       ↓  18/24 层 Transformer
Encoder Output [n_tokens × 896/1024]  ← 每 ~40ms 一个 token
       ↓
嵌入到 Decoder 的 input_embeds 中
```

800 帧（8 秒音频）经过 encoder 后压缩为约 200 个 encoder token，然后拼接 prefix/suffix tokens 一起送入 LLM decoder 做自回归解码。

### 与 Whisper 的对比

Qwen3-ASR 的 mel 计算与 Whisper 几乎相同（因为 audio tower 源自 Whisper 架构），唯一区别是 mel bin 数：

| | Whisper | Qwen3-ASR |
|--|---------|-----------|
| Mel bins | 80 | **128** |
| N_FFT | 400 | 400 |
| HOP_LENGTH | 160 | 160 |
| 采样率 | 16kHz | 16kHz |

Qwen3-ASR 用 128 维而非 80 维，保留了更多高频细节信息。
