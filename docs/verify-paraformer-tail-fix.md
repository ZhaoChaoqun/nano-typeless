# verify_paraformer_tail_fix.py — FunASR is_final 机制验证

## 目的

验证 FunASR 的 `is_final=True` 机制能否修复 Streaming Paraformer 的尾部 token 截断问题，并通过三组对照实验定位截断的根因：

1. **sherpa-onnx 流式（基线）**：已知存在尾部截断
2. **FunASR 流式 + `is_final=True`**：最后一个 chunk 标记为 final，触发 CIF tail flush
3. **FunASR 流式 + `is_final=False`（消融对照）**：所有 chunk 同等对待，验证 `is_final` 的因果关系

## 验证方法

### sherpa-onnx 基线

使用 `sherpa_onnx.OnlineRecognizer.from_paraformer()` 做标准流式推理：
- 600ms chunk（9600 samples @ 16kHz）
- 音频送完后追加 1s 静音 padding
- 调用 `input_finished()` 标记结束

### FunASR 流式

使用 `funasr.AutoModel` 的 `paraformer-zh-streaming` 模型（v2.0.4）：
- chunk 配置：`[0, 10, 5]`（左上下文 0, 中心 10 帧, 右上下文 5 帧）
- `encoder_chunk_look_back=4`, `decoder_chunk_look_back=1`
- chunk stride = 9600 samples（600ms）
- `is_final` 参数在最后一个 chunk 上设为 True 或 False

### 对照逻辑

对每条音频检查尾部关键词是否出现在输出中：
- sherpa-onnx 截断 + FunASR final 恢复 → 确认 `is_final` 是修复机制
- sherpa-onnx 截断 + FunASR final 也截断 → 问题在更底层（encoder 精度或 chunk 边界）
- 三者都不截断 → 该音频不受影响

## 测试用例

| ID | 音频 | 期望尾部关键词 | 完整期望文本 |
|----|------|----------------|-------------|
| cs_edge_008 | codeswitching/cs_edge_008.wav | "test" | CI pipeline跑了30分钟，还没通过unit test。 |
| wenet_net_001 | wenetspeech/wenet_net_001.wav | "觉" | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 |
| ascend_cs_003 | ascend/ascend_cs_003.wav | "opportunity" | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 |

## 验证结论

### FunASR `is_final=True` 成功恢复全部 3 条截断 token

| ID | 关键词 | sherpa-onnx | FunASR final | FunASR no-final |
|----|--------|:-----------:|:------------:|:---------------:|
| cs_edge_008 | test | ✗ | **✓ 恢复** | ✗ 截断 |
| wenet_net_001 | 觉 | ✗ | **✓ 恢复** | ✗ 截断 |
| ascend_cs_003 | opportunity | ✗ | **✓ 恢复** | ✗ 截断 |

- **sherpa-onnx 3/3 截断**：所有三条音频的尾部关键词都丢失。
- **FunASR `is_final=True` 3/3 恢复**：最后一个 chunk 传入 `is_final=True` 后，全部尾部 token 恢复。
- **FunASR `is_final=False` 3/3 截断**：消融对照确认 `is_final` 机制是关键因素。

### `is_final` 的内部机制

FunASR 的 `is_final=True` 在最后一个 chunk 上触发以下行为：
1. **不对右上下文 alpha 置零**：保留最后 chunk 右上下文区域的 CIF alpha 信息
2. **CIF tail flush**：将累积的残余 alpha（< 1.0）强制 fire，产生最后一个 acoustic embedding
3. 这两步恰好对应了 sherpa-onnx 缺失的两项功能

## 启发

1. **sherpa-onnx 缺失 `is_final` 是流式 Paraformer 尾部截断的直接根因**。FunASR 的实现证明了，只要在最后一个 chunk 上跳过右上下文 alpha 零化并执行 CIF tail flush，就能完整恢复尾部 token。

2. **消融实验（`is_final=False`）的价值**：3/3 截断确认了这不是偶然恢复，而是 `is_final` 机制本身的因果效果。

3. **sherpa-onnx 的三层截断问题被验证**：
   - (A) `IsReady()` 门控丢弃不足 62 帧的末尾音频
   - (B) 右上下文 alpha 零化在最后一个 chunk 上销毁有效 token
   - (C) CIF 无 `tail_threshold`，残余 alpha 被静默丢弃

   FunASR 的 `is_final` 同时修复了 (B) 和 (C)，而 (A) 通过允许短 chunk 进入 encoder 来解决。

4. **迁移方向明确**：要在我们的实现中修复截断，需要在 final chunk 处理中引入类似 FunASR 的 `is_final` 逻辑——具体来说就是跳过右上下文 alpha 零化 + CIF tail_threshold=0.45 flush。

## 依赖

```bash
uv run --with funasr --with soundfile --with sherpa-onnx \
    python3 scripts/verify_paraformer_tail_fix.py
```

需要 sherpa-onnx 模型在 `~/Library/Application Support/Nano Typeless/models/`。
FunASR 会自动从 ModelScope 下载 `paraformer-zh-streaming` 模型。
