# 长音频流式 CER 优化实验报告

## 背景

Qwen3-ASR 流式模式在短音频（<15s）上表现良好（CER≈0），但在 30s 和 60s 长音频上 CER 严重退化：

- `long_30s_01` CER ≈ 0.52–0.57
- `long_60s_01` CER ≈ 0.65–0.86

典型表现为"循环后截断"——输出包含开头几句正确内容，中间大段丢失，尾部碎片拼接。

## 当前架构（增量 Encoder Cache + Re-anchor）

`stream_push_audio` 的核心流程：

```
每个 chunk（2s 音频）:
  1. Encoder: 增量编码新 window（8s 一个），结果缓存在 enc_cache
  2. 拼接全部 enc_cache → enc_output
  3. 构建 input_embeds: [PREFIX | enc_output | SUFFIX | past_text_tokens]
  4. Decoder prefill (LCP reuse) + autoregressive decode (max_new_tokens 步)
  5. Rollback: 保留 raw_tokens[0..len-rollback] 作为下一 chunk 的 prefix
  6. Degeneracy detection: 检测输出重复，触发 reset
  7. Re-anchor: 当 enc_seq_len >= 200 时，清空 decoder 状态 + 丢弃旧 encoder windows（只保留最后 1 个）
  8. Emit stable tokens
```

**Re-anchor 时丢弃旧 encoder windows 是长音频信息丢失的直接原因。**

## 深度代码审查（三个嫌疑点）

用户要求对 Rust 实现做 Transformer 底层审查，排查三个嫌疑点。

### 嫌疑 A：KV Cache 与 Token Rollback 同步性

**审查文件**: `transcribe.rs:1065-1144`, `decoder.rs:436-497`

**结论：无 Bug。**

KV Cache 不是通过"截断"来同步 rollback 的，而是通过 LCP (Longest Common Prefix) embedding 比较间接实现。每个 chunk 的 encoder output 都不同（新音频），LCP 比较在 PREFIX_HEAD（3 个 token）后就断开，`reused_prefill ≈ 3`。整个序列从 position 3 重新 prefill，旧 KV 被新值完全覆盖。

关键代码路径：
```
rollback → n_prefix_tokens = (raw_tokens.len() - rollback).max(0)
         → input_embeds 末尾放入 n_prefix_tokens 个 token embedding
         → LCP 比较 prev_prefill_embeds vs input_embeds → reused_prefill ≈ 3
         → kv_cache.len = reused_prefill
         → decoder_prefill(delta) 从 reused_prefill 开始覆写 KV Cache
```

### 嫌疑 B：RoPE 位置编码连续性

**审查文件**: `decoder.rs:436-439` (prefill), `decoder.rs:521-529` (forward)

**结论：无 Bug。**

> **什么是 RoPE（Rotary Position Embedding）？**
>
> Transformer 模型处理一串 token 时，模型本身并不知道每个 token 在序列中的"位置"——它只看到一组向量，分不清谁先谁后。RoPE 是一种告诉模型"这个 token 排第几"的技术。
>
> 具体做法是：根据 token 的位置编号，对它的向量做一个**旋转变换**（类似把向量在平面上转一个角度）。位置越靠后，旋转的角度越大。这样模型在计算注意力时，就能从向量的旋转角度差异中"感知"到两个 token 之间的距离——相邻 token 角度差小，距离远的 token 角度差大。
>
> 这里的关键要求是：**位置编号必须连续递增**（0, 1, 2, 3, …）。如果位置出现跳跃（比如从 5 突然跳到 100）或意外重置为 0，模型就会"误判"token 之间的距离，导致注意力计算混乱、输出质量下降。

RoPE position 完全由 `kv_cache.len` 驱动。prefill 使用 `start_pos = kv_cache.len` 作为 RoPE 起点，forward 使用 `pos = kv_cache.len`。位置始终从 LCP reuse 点连续递增，不存在跳跃或重置为 0 的问题。

```rust
// decoder.rs:436 (prefill)
let start_pos = kv_cache.len;
rope.ensure(start_pos + seq_len, head_dim, theta);
let rope_cos = rope.cos_range(start_pos, seq_len);

// decoder.rs:521 (forward)
let pos = kv_cache.len;
rope.ensure(pos + 1, head_dim, theta);
let rope_cos = rope.cos_at(pos);
```

### 嫌疑 C：Re-anchor 后 Encoder Cache 信息丢失

**审查文件**: `transcribe.rs:1297-1307`

**结论：这是根本原因。**

```rust
// re-anchor 时：
let keep_windows = 1.min(state.enc_cache.len());
let drop_windows = state.enc_cache.len() - keep_windows;
// → 丢弃所有旧 encoder windows，只保留最后 1 个（~8s 音频）
```

对于 30s 音频，re-anchor 后 decoder 只看到最后 ~8s 的 encoder output，前面 70%+ 的内容对 decoder 不可见。

## 实验 1：Re-encode All 策略

### 思路

模仿官方 vLLM streaming 实现——每个 chunk 重新编码全部累积音频（`samples[0..audio_cursor]`），不使用增量 encoder window cache。这样 re-anchor 只重置 decoder token 状态，不丢失任何 encoder 信息。

官方代码参考（`qwen_asr/inference/qwen3_asr.py`）：
```python
state.audio_accum = np.concatenate([state.audio_accum, chunk], axis=0)
# 整个 audio_accum 传给模型
```

### 修改内容

文件：`crates/qwen-asr/src/transcribe.rs`

1. 替换增量 encoder 逻辑为全量重新编码
2. 删除 re-anchor 和 degeneracy reset 中的 encoder cache 丢弃
3. 调整 re-anchor 触发条件

### 测试变体与结果

使用 Python benchmark（`scripts/benchmark_engines.py`）快速验证，chunk_sec=2.0。

#### 变体 A：Re-encode all + 无 re-anchor（只保留 chunk 间隔触发）

| 测试 | max_new_tokens | CER | 耗时 |
|------|---------------|-----|------|
| long_30s_01 | 32 | 0.649 | 77s |
| long_60s_01 | 32 | 0.839 | 205s |

**结果**：比 baseline 更差。Decoder 面对不断增长的 encoder 序列（30s≈390 tokens, 60s≈780 tokens）严重退化，出现大量重复输出（"已经广泛应用于智能手机和" 重复 3 次）。

#### 变体 B：Re-encode all + enc_seq 阈值 re-anchor @200 + max_new_tokens=32

| 测试 | CER | 耗时 |
|------|-----|------|
| long_30s_01 | 0.675 | 117s |
| long_60s_01 | 0.859 | 343s |

**结果**：仍然更差。re-anchor 虽然重置了 decoder 状态，但 encoder output 仍然太长，decoder 重新启动后依旧面对长序列退化。

#### 变体 C：Re-encode all + enc_seq 阈值 re-anchor @200 + max_new_tokens=128

| 测试 | CER | 耗时 |
|------|-----|------|
| long_30s_01 | 0.675 | 126s |
| long_60s_01 | 0.818 | 387s |

**结果**：增大 max_new_tokens 略有帮助但不显著。根本问题是 decoder 对长 encoder 序列的处理能力有限。

### Re-encode All 结论

**策略彻底失败。** 原因：

1. **Decoder 在 CPU 上无法有效处理长 encoder 序列**——这不是 encoder 信息丢失问题，而是 decoder 本身的能力限制
2. **CPU 性能开销暴增 3-7x**——每个 chunk 都要重新编码全部音频
3. 官方 vLLM 方案之所以可行，依赖 GPU 推理和无 max_new_tokens 限制，二者在 CPU 环境下都不具备

## 实验 2：增大 max_new_tokens

### 思路

保持原始增量 encoder cache 架构不变，仅增大 `max_new_tokens`，让 decoder 在每个 chunk 有更多解码步数，在 re-anchor 触发前尽可能多地把 encoder 内容解码出来。

### 测试结果

| max_new_tokens | long_30s CER | long_60s CER | 30s 耗时 | 60s 耗时 |
|---------------|-------------|-------------|---------|---------|
| 32 (baseline) | 0.515 | 0.654 | ~30s | ~56s |
| **128** | **0.469** | **0.496** | ~31s | ~58s |
| 256 | 0.469 | 0.496 | ~31s | ~58s |

### 分析

- **32→128：long_60s CER 从 0.654 降到 0.496，改善 24%**
- 128→256 无额外收益，说明 128 步已足够 decoder 输出 EOS
- **性能几乎无损**——耗时仅增加 ~3%，因为 decoder 通常在 EOS 前就停止
- 输出质量明显改善：更多正确句子被保留

## 全部实验汇总表

| # | 策略 | max_new_tokens | long_30s CER | long_60s CER | 30s 耗时 | 备注 |
|---|------|---------------|-------------|-------------|---------|------|
| 1 | 增量 encoder + keep 1 | 32 | 0.515 | 0.654 | ~30s | baseline |
| 2 | **增量 encoder + keep 1** | **128** | **0.469** | **0.496** | **~31s** | **最佳** |
| 3 | 增量 encoder + keep 1 | 256 | 0.469 | 0.496 | ~31s | 同 #2 |
| 4 | re-encode all, no re-anchor | 32 | 0.649 | 0.839 | ~77s | 退化 |
| 5 | re-encode all + re-anchor@200 | 32 | 0.675 | 0.859 | ~117s | 退化 |
| 6 | re-encode all + re-anchor@200 | 128 | 0.675 | 0.818 | ~126s | 退化 |

## 结论与建议

### 已确认

1. **KV Cache 和 RoPE 实现无 Bug**——Rollback 通过 LCP prefill reuse 间接同步，position 连续递增
2. **Re-anchor 丢弃 encoder windows 是信息丢失的直接原因**，但无法简单修复——decoder 在 CPU 上处理长 encoder 序列会退化
3. **Re-encode all 官方策略在 CPU 上不可行**——性能和质量双失
4. **增大 max_new_tokens 是当前最有效的优化**——将 long_60s CER 从 0.654 降到 0.496，无性能损耗

### 建议操作

**短期（立即可做）**：将 Swift 侧 `max_new_tokens` 从 32 改为 128（一行改动）。

```swift
// Sources/QwenASRRecognizer.swift
qwen_asr_stream_set_max_new_tokens(engine, 128)  // 原值 32
```

### 长期可探索方向

1. **GPU 推理**：通过 Metal / CoreML / MLX 加速 decoder，使其能处理长 encoder 序列
2. **Encoder Cache 智能压缩**：不是丢弃旧 windows，而是对旧 encoder output 做 downsampling/pooling 压缩，保留关键信息
3. **分段 + 拼接**：30s+ 音频自动分段成 15s 片段独立识别，最后拼接结果（牺牲跨段连贯性）

## 附录：测试环境

- 机器：MacBook Pro M4
- 模型：Qwen3-ASR-0.6B INT8
- Rust 编译：`RUSTFLAGS="-C target-cpu=native" cargo build --release`
- 测试工具：`scripts/benchmark_engines.py`（Python ctypes 直接调用 dylib）
- Benchmark 参数：chunk_sec=2.0, rollback=3, unfixed_chunks=1
- 日期：2026-03-03
