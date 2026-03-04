# Qwen3-ASR 流式 Decoder Degeneracy 问题分析报告

*生成时间：2026-03-02*

## 1. 问题概述

Qwen3-ASR 流式模式在长音频（>15s）上会出现**文本重复**现象。例如：

| 条目 | 期望文本（截取） | 流式输出 | CER |
|------|-----------------|---------|-----|
| long_30s_01 | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解自然语言。语音识别技术... | 人工智能技术在过去十年中取得了巨大的进步。深度学习算法使得计算机能够处理。**人工智能技术在过去十年中取得了巨大的进步。深度学习算法** | 0.758 |
| long_60s_01 | 软件工程是一门研究用工程化方法构建和维护... | 软件工程是一门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。**软件工程是一门研究用** | 0.877 |
| zh_long_01 | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析。 | 人工智能正在深刻地改变我们的生活方式。从语音识别到自动驾驶，从医疗诊断到金融。**人工智能正在深刻地改变我们的生活方式，从** | 0.537 |

同样的音频在离线模式（`transcribeOffline`, segment_sec=20s）下不会重复，CER 分别为 0.010、0.009、0.000。

---

## 2. 流式引擎架构

### 2.1 核心思路

Qwen3-ASR 流式采用 **chunk + rollback** 方案：把连续音频切成固定长度的 chunk（`chunk_sec=1.5s`），每个 chunk 过一次 encoder + decoder：

```
音频流:  [----chunk 0----][----chunk 1----][----chunk 2----] ...
encoder:      encode(0)        encode(0,1)      encode(0,1,2)
decoder:      decode → tok     decode → tok      decode → tok
rollback:     不输出            输出(减去尾部3)    输出(减去尾部3)
```

### 2.2 关键参数

| 参数 | 当前值 | 含义 |
|------|-------|------|
| `chunk_sec` | 1.5s | 每个 chunk 的音频长度 |
| `rollback` | 3 | 每次 decode 后保留尾部 3 个 token 不 commit（可能被下一个 chunk 修正） |
| `unfixed_chunks` | 1 | 前 1 个 chunk 完全不 commit（等待更多上下文） |
| `max_new_tokens` | 32 | decoder 每个 chunk 最多生成 32 个 token |
| `STREAM_RESET_INTERVAL_CHUNKS` | 45 | 每 45 个 chunk（67.5s）强制 re-anchor |
| `STREAM_RESET_CARRY_TOKENS` | 24 | re-anchor 时保留最近 24 个 stable token 作为上下文 |
| `STREAM_MAX_ENC_WINDOWS` | 4 | encoder cache 最大 4 个窗口 |

### 2.3 StreamState 核心字段

```
┌─────────────────────────────────────────────────┐
│ StreamState                                     │
├─────────────────────────────────────────────────┤
│ raw_tokens       当前活跃 token 历史             │
│ stable_text_tokens  已 commit 到用户的 token     │
│ result_bytes     已 commit 文本的 UTF-8 字节     │
│ enc_cache        缓存的 encoder 窗口输出         │
│ audio_cursor     已处理到的音频样本位置           │
│ prev_prefill_embeds  上一次 prefill 的 embedding │
│ stale_count      连续未变化 chunk 计数器         │
│ prev_tail_snapshot   上一次 raw_tokens 快照      │
│ chunk_idx        当前 chunk 序号                 │
└─────────────────────────────────────────────────┘
```

### 2.4 每个 chunk 的处理流程

```
对每个 chunk:
  1. encoder: 编码新的音频帧，追加到 enc_cache
  2. prefill: 拼接 [prompt | enc_output | raw_tokens] 填入 decoder KV cache
     └─ LCP 优化: 与上次 prefill 对比，跳过相同前缀
  3. autoregressive decode: 最多生成 max_new_tokens 个 token
  4. 更新 raw_tokens: truncate(保留尾部 rollback 个) + append(新 token)
  5. degeneracy 检测
  6. 周期性 re-anchor 检查
  7. token emission: 根据 candidate_len 将 token commit 到 stable_text_tokens
```

---

## 3. Degeneracy（退化/幻觉）的产生机制

### 3.1 什么是 Decoder Degeneracy

Decoder degeneracy 是指 autoregressive decoder 在生成 token 时**陷入重复循环**——不断输出之前已经生成过的 token 序列。这是 Transformer decoder 的一个已知问题，在长序列生成中尤为典型。

在 ASR 场景中表现为：decoder 在处理后续音频时，不再根据新的 encoder 输出生成新文本，而是重复之前已经"说过"的内容。

### 3.2 为什么流式比离线更容易退化

| 维度 | 离线模式 | 流式模式 |
|------|---------|---------|
| encoder 上下文 | 一次性看到整段音频（≤20s） | 逐 chunk 累积，每次只新增 1.5s |
| decoder 输入 | 完整 encoder 输出 + 全局注意力 | 累积的 encoder 窗口 + 截断的 token 历史 |
| KV cache | 每段独立，不跨段累积 | 跨 chunk 复用（通过 LCP 优化延续） |
| token 历史 | 完整、连贯 | 只保留 rollback 窗口（3 token） |
| 分段策略 | `segment_sec=20s`，在低能量点切分 | 无分段，一路流式到底 |

**关键差异**：离线模式用 `transcribe_audio` 将长音频按 `segment_sec=20s` 自动分段，每段独立调 `transcribe_segment`，encoder 一次看完整段、decoder 从头开始。流式模式则是连续增量处理，decoder 的 KV cache 不断累积。

### 3.3 退化的具体触发路径

以 `long_30s_01`（30 秒音频）为例，`chunk_sec=1.5s` 会产生约 20 个 chunk：

```
chunk 0:  encoder cache=[win0]  raw_tokens=[]
chunk 1:  encoder cache=[win0,win1]  raw_tokens=[t0,t1,t2]  → 输出: 无 (unfixed_chunks=1)
chunk 2:  encoder cache=[win0,win1,win2]  raw_tokens=[rollback+new]  → 输出: commit 部分 token
...
chunk 10: encoder cache=[win0..win10]  → KV cache 已累积 ~300+ 位置
          decoder 的注意力分散在越来越长的 encoder 输出上
...
chunk 15-20:
  → encoder 输出中新帧的权重被历史帧"稀释"
  → decoder 注意力可能"锁定"到早期 encoder 窗口
  → 生成的 token 开始重复之前的文本
```

**核心矛盾**：随着 chunk 数增加，encoder cache 线性增长，decoder 的 cross-attention 在越来越长的 encoder 序列上计算。当 encoder 序列达到某个临界长度后，decoder 的注意力分散导致其更倾向于"回忆"之前的 token 而非跟随新的 encoder 输出。

### 3.4 rollback + re-anchor 的上下文断裂

每个 chunk 处理后，`raw_tokens` 被 truncate 到只保留最后 `rollback=3` 个 token（`transcribe.rs:1255`）：

```rust
state.raw_tokens.truncate(n_prefix_tokens);  // n_prefix_tokens = max(0, len - rollback)
state.raw_tokens.extend_from_slice(&chunk_tokens);
```

这意味着 decoder 在下一个 chunk 的 prefill 阶段只看到**最近 3 个 token + 新 chunk 的 decode 结果**作为文本上下文。当这 3 个 token 恰好是句子的常见结尾模式时，decoder 可能将其解读为"句子开头"，从而重新生成之前的内容。

---

## 4. 现有防护机制及其局限

### 4.1 Degeneracy 检测（`transcribe.rs:1258-1268`）

两个独立的检测触发器：

**触发器 A — Stale 检测**：
```rust
if state.raw_tokens == state.prev_tail_snapshot {
    state.stale_count += 1;
}
let is_degen = state.stale_count >= STREAM_STALE_CHUNKS;  // ≥ 4 次完全相同
```
- 检测 `raw_tokens` 是否连续 4 个 chunk 完全不变
- **局限**：如果 decoder 交替产生两种不同的重复序列（A → B → A → B），`stale_count` 永远 ≤ 1，无法触发

**触发器 B — 尾部重复块检测**：
```rust
let (best_reps, _) = stream_tail_repeat_blocks(&state.raw_tokens, STREAM_DEGEN_MAX_PERIOD);
let is_degen = best_reps >= STREAM_DEGEN_MIN_REPEATS;  // 周期≤6 的模式重复≥4 次
```
- 检测 `raw_tokens` 尾部是否有短周期（≤6 token）的重复模式
- **局限**：
  - `raw_tokens` 在每个 chunk 后被 truncate 到 rollback(3) + 新 token（典型 3-6 个），总长度约 6-9 token
  - 周期为 6 的模式需要至少 `4 × 6 = 24` token 才能检测到 4 次重复，但 `raw_tokens` 最多只有 ~9 token
  - 实际上**只能检测到非常短周期（1-2 token）的重复**，如 `[的, 的, 的, 的]`
  - 长周期重复（如重复一整个句子）**完全无法检测**

### 4.2 周期性 Re-anchor（`transcribe.rs:1293-1314`）

每 45 个 chunk（67.5s）强制重置：

```rust
if state.chunk_idx > 0 && state.chunk_idx % 45 == 0 {
    // 清空 raw_tokens，保留最近 24 个 stable token
    // 清空 encoder cache
    // 清空 prefill cache
}
```

**局限**：
- 45 × 1.5s = 67.5s，但退化在 ~10-15s 就开始了
- 30s 音频 = 20 chunk，re-anchor 永远不会触发
- 即使触发，之前已经 commit 到 `stable_text_tokens` 的重复文本**无法撤回**

### 4.3 Speech-ended 检测（`transcribe.rs:1222-1224`）

```rust
let speech_ended = chunk_tokens.is_empty()  // decoder 产生 EOT
    && !state.raw_tokens.is_empty()
    && state.chunk_idx >= unfixed_chunks;
```

当 decoder 在最终 silence 上产生 EOT 时触发，flush 所有 rollback token。

**局限**：只在流结束时生效，不能阻止中间过程的退化。

---

## 5. 退化的根因图

```
┌─────────────────────────────────────────────────────────────────┐
│                    流式长音频退化链                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ① encoder cache 线性增长                                       │
│     chunk_sec=1.5s, 20 chunks → ~30s 的 encoder 输出累积        │
│     ↓                                                           │
│  ② decoder cross-attention 在越来越长的 encoder 序列上运算       │
│     注意力被历史帧稀释，新帧的贡献降低                            │
│     ↓                                                           │
│  ③ decoder 开始"回忆"早期 encoder 窗口对应的文本                 │
│     生成与之前相同的 token 序列                                   │
│     ↓                                                           │
│  ④ raw_tokens 只保留 3 个 rollback token                        │
│     上下文太短，无法制约 decoder 的重复倾向                       │
│     ↓                                                           │
│  ⑤ degeneracy 检测在 ~9 token 的 raw_tokens 上运行              │
│     无法检测句子级别的长周期重复                                   │
│     ↓                                                           │
│  ⑥ 重复 token 被 commit 到 stable_text_tokens                   │
│     不可撤回                                                     │
│     ↓                                                           │
│  ⑦ result_bytes 中出现重复文本                                   │
│                                                                 │
│  [ re-anchor 间隔 67.5s >> 退化开始时间 ~10-15s ]               │
│  [ re-anchor 无法撤回已 commit 的重复文本 ]                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 为什么离线模式不受影响

离线模式 `transcribeOffline` 调用链：

```
transcribeOffline(samples, segmentSec=20.0)
  → Rust: qwen_asr_transcribe_pcm()
    → transcribe_audio()
      → 按 segment_sec=20s 自动分段（在低能量点切分）
        → 对每段独立调 transcribe_segment()
          → 一次性 encoder(整段) + decoder(整段)
          → decoder 看到完整 encoder 输出，一次解码完成
```

关键区别：
1. **每段只有 ≤20s**：encoder 输出长度有上限
2. **encoder 一次性编码整段**：不存在增量累积的问题
3. **decoder 一次解码**：KV cache 不跨段复用，无累积退化
4. **段间独立**：前一段的 decoder 状态不影响下一段

---

## 7. 修复方案

### 方案 A：降低 re-anchor 间隔（Rust 侧，推荐）

将 `STREAM_RESET_INTERVAL_CHUNKS` 从 45 降到 **8-10**（12-15s），让 re-anchor 在退化发生前主动触发。

```rust
// transcribe.rs:21
// 修改前
const STREAM_RESET_INTERVAL_CHUNKS: i32 = 45;
// 修改后
const STREAM_RESET_INTERVAL_CHUNKS: i32 = 10;  // 10 × 1.5s = 15s
```

**优点**：直接解决根因，限制 encoder cache 和 KV cache 的最大长度
**缺点**：需要重编 Rust dylib；re-anchor 时有短暂的上下文断裂（约 1-2 个 token 可能不准确）
**预期效果**：流式长音频 CER 应大幅下降，接近离线模式的 segment_sec=20s 效果

### 方案 B：增强 degeneracy 检测（Rust 侧）

在 `result_bytes` 层面检测句子级重复，而不仅仅在 `raw_tokens` 层面检测 token 级重复。

```rust
// 在 token emission 后新增：检查最近 commit 的文本是否与之前文本重复
let recent_text = &result_bytes[result_bytes.len().saturating_sub(recent_window)..];
let earlier_text = &result_bytes[..result_bytes.len().saturating_sub(recent_window)];
if text_overlap_ratio(recent_text, earlier_text) > 0.8 {
    // 回滚最近 commit 的 token
    // 触发 re-anchor
}
```

**优点**：精确检测句子级重复
**缺点**：实现复杂；需要定义"重复"的阈值；回滚已 commit 的 token 需要修改 `stable_text_tokens` 和 `result_bytes`（当前设计不支持回滚）

### 方案 C：限制 encoder cache 长度（Rust 侧）

将 `STREAM_MAX_ENC_WINDOWS` 从 4 降到 2-3，更频繁地清理 encoder cache。

```rust
// transcribe.rs:23
const STREAM_MAX_ENC_WINDOWS: usize = 2;  // 从 4 降到 2
```

**优点**：限制 cross-attention 的最大长度
**缺点**：encoder cache 清理不触发 re-anchor（只在 re-anchor 时才检查），需要配合方案 A

### 方案 D：Swift 侧后处理去重（Swift 侧，兜底）

在 `QwenASREngine.flush()` 返回结果前，检测并移除句子级重复。

```swift
func deduplicateText(_ text: String) -> String {
    // 检测 text 的后半段是否是前半段的前缀重复
    // 如果是，截取到第一次出现的位置
}
```

**优点**：不改 Rust，纯 Swift 层面
**缺点**：只能兜底处理 flush 时的重复，无法修复流式过程中 `getResult()` 已经返回的重复文本；可能误删合法的重复内容

### 推荐实施顺序

1. **方案 A**（降低 re-anchor 间隔）— 最小改动，最大收益
2. **方案 C**（限制 encoder cache）— 配合方案 A
3. **方案 D**（Swift 去重兜底）— 作为安全网
4. **方案 B**（增强检测）— 长期优化

---

## 8. 对比实验数据

来自 benchmark 运行（67 条测试音频）：

| Pipeline | 平均 CER | CER=0 | CER≤0.10 | CER>0.20 |
|----------|---------|-------|----------|----------|
| Qwen3-ASR (离线, segment=20s) | **0.0573** | 34/67 | 50 | 4 |
| Qwen3-ASR (流式, 0.1s silence+finalize) | **0.0944** | 34/67 | 47 | 9 |

流式与离线的差距主要来自 3 个长音频条目（CER 0.537/0.758/0.877），其余短音频（<10s）两者表现基本一致。

---

## 9. 短期可用性评估

| 使用场景 | 流式表现 | 说明 |
|---------|---------|------|
| 短句（<5s） | ✅ 优秀 | 与离线一致，CER ≈ 0 |
| 中等句子（5-15s） | ✅ 良好 | 偶有尾部字词差异 |
| 长语音（15-30s） | ⚠️ 有风险 | 可能出现句子级重复 |
| 超长语音（>30s） | ❌ 不可用 | 大概率退化 |

在实际产品中，用户通常按住 Fn 键说一句话（3-10s），流式模式在这个范围内表现正常。degeneracy 问题主要影响长时间连续录音场景。
