# verify_streaming_chunk_truncation.py — 流式 Chunk 推理截断机制复现

## 目的

用原生 ONNX Runtime **模拟 sherpa-onnx 的流式 chunk-by-chunk 推理**，直接复现 cs_edge_008 和 wenet_net_001 的尾部截断现象，并通过消融实验隔离 **右上下文 alpha 零化**是否是截断的直接原因。

## 验证方法

### sherpa-onnx 流式参数（硬编码还原）

| 参数 | 值 | 说明 |
|------|:--:|------|
| CHUNK_SIZE | 61 | 每个 chunk 的原始 fbank 帧数（≈0.61s） |
| LEFT_CHUNK | 5 | 左上下文 LFR 帧数 |
| RIGHT_CHUNK | 3 | 右上下文 LFR 帧数 |
| lfr_chunk_size | 10 | 每个 chunk 的有效 LFR 帧数 |

### 推理流程

1. 对全部音频提取 fbank → LFR → CMVN（预处理不分 chunk）
2. 将 LFR 特征按 `lfr_chunk_size=10` 切分为多个 chunk
3. 每个 chunk 拼接左上下文（5 帧）和右上下文（3 帧），共 18 LFR 帧
4. 送入 encoder 得到 `enc [18, 512]` 和 `alphas [18]`
5. **模式 A**（alpha 置零）：将左右上下文区域的 alphas 置 0，模拟 sherpa-onnx 行为
6. **模式 B**（不置零）：保留全部 alphas，作为消融对照
7. 只取中心区域（10 帧）的 encoder 输出拼接
8. CIF 积分（无 tail_threshold，模拟 sherpa-onnx 默认行为）
9. Decoder 解码得到文本

### 两种模式对比

- **模式 A（zero_right_context=True）**：模拟 sherpa-onnx 的 `std::fill(alpha + left, 0)` 和 `std::fill(alpha + right, 0)` 行为
- **模式 B（zero_right_context=False）**：消融对照，不置零任何 alpha

## 测试用例

| ID | 音频 | 期望尾部关键词 |
|----|------|----------------|
| cs_edge_008 | codeswitching/cs_edge_008.wav | "test" |
| wenet_net_001 | wenetspeech/wenet_net_001.wav | "觉" |

## 验证结论

### cs_edge_008：chunk 边界效应导致截断

| 模式 | 输出 | 包含 "test" |
|------|------|:-----------:|
| A（alpha 置零） | 缺失 "test" | ✗ |
| B（不置零） | 缺失 "test" | ✗ |

两种模式都截断了 "test"。说明 **alpha 零化不是 cs_edge_008 截断的直接原因**。

深入分析发现：将音频切分为多个 chunk 后，encoder 在 chunk 边界处产生异常的 alpha spike（离线模式下 frame 72 的 alpha 为 0.0006，流式模式下变为 0.9999）。这种 chunk 边界效应扰乱了整体 CIF 积分，即使不置零 alpha，"test" 对应的 token 也无法正确 fire。

### wenet_net_001：模拟未能完全复现 sherpa-onnx 行为

| 模式 | 输出 | 包含 "觉" |
|------|------|:---------:|
| A（alpha 置零） | 包含 "觉" | ✓ |
| B（不置零） | 包含 "觉" | ✓ |

模拟中两种模式都未截断。但 sherpa-onnx 实际运行时 wenet_net_001 确实会截断 "觉"。这表明 **模拟还不够精确**——sherpa-onnx 的真实实现有以下差异：

1. **Raw frame 级别的 chunk 切分**：sherpa-onnx 在 raw fbank 帧（而非 LFR 帧）级别做 chunk 划分，每次 advance 60 帧（1-frame overlap）
2. **IsReady() 门控**：`num_processed + 61 < num_ready`（严格小于，需要累积到 62 帧才能触发），末尾不足 62 帧的音频被丢弃
3. **特征缓存机制**：sherpa-onnx 维护 feat_cache（8 LFR 帧），跨 chunk 携带，影响 LFR 拼接

### 后续 sherpa-onnx 源码分析补充

通过分析 sherpa-onnx C++ 源码（`online-paraformer-model.cc`、`online-paraformer-decoder.cc`），确认了完整的截断机制：

| 截断源 | 机制 | 影响 |
|--------|------|------|
| IsReady() 门控 | `num_processed + 61 < num_ready`，丢弃末尾 < 62 帧 | 最多 610ms 音频 |
| 右上下文 alpha 零化 | `std::fill(p_alpha + T - 3, p_alpha + T, 0)` 在每个 chunk 执行 | 最后 chunk 丢失 ~180ms |
| CIF 无 tail flush | 残余 alpha < 1.0 被静默丢弃，无 `tail_threshold` | 丢失最后 1 个 partial token |

三者叠加，最坏情况下可丢失约 800ms 音频内容。

## 启发

1. **流式 chunk 推理的截断是多因素叠加**：不能简单归因于 alpha 零化。cs_edge_008 的截断主要来自 chunk 边界对 encoder 注意力模式的干扰；wenet_net_001 的截断则与 IsReady() 门控和 raw frame 级别的调度有关。

2. **仅靠 LFR 级别的 chunk 模拟不够精确**：要完全复现 sherpa-onnx 行为，需要在 raw fbank frame 级别实现 chunk 调度，包括 1-frame overlap、IsReady 条件、fbank 特征缓存等全部细节。

3. **消融实验的方法论价值**：尽管模拟不够精确，但 A/B 对照确认了 alpha 零化不是 cs_edge_008 截断的唯一原因——这推动了后续更深入的 sherpa-onnx 源码分析。

4. **修复方案需要综合应对三个截断源**：
   - (A) 允许短 chunk 进入 encoder（移除 IsReady 门控的 62 帧下限）
   - (B) 在最后一个 chunk 上不对右上下文 alpha 置零
   - (C) 在最终 CIF 积分中使用 `tail_threshold=0.45` flush 残余 token

## 依赖

```bash
uv run --with onnxruntime --with kaldi-native-fbank --with soundfile \
    python3 scripts/verify_streaming_chunk_truncation.py
```

依赖 `verify_onnx_tail_fix.py` 中的基础函数（`load_audio`, `extract_fbank`, `apply_lfr`, `apply_cmvn`, `load_tokens`, `ids_to_text`, `cif_integrate`）。
