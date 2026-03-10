# verify_onnx_tail_fix.py — ONNX Runtime 离线推理精度验证

## 目的

用原生 ONNX Runtime 绕过 sherpa-onnx 的流式 chunk 调度，对 Streaming Paraformer 的 encoder 和 decoder 进行**离线全量推理**，验证：

1. **int8 量化精度损失是否导致尾部 token 丢失**（对比 int8 / fp32 / fp16 encoder）
2. **CIF `tail_threshold=0.45` 是否能恢复丢失的尾部 token**
3. **模型精度 vs 模型大小的权衡**

## 验证方法

脚本模拟完整的 Paraformer ASR pipeline，但跳过流式 chunk 切分，直接对全部音频特征做一次性推理：

```
音频 → Fbank(80-dim, kaldi-native-fbank) → LFR(7/6) → CMVN → Encoder → CIF 积分 → Decoder → 文本
```

对每条测试音频，分别运行：
- **无 tail_threshold**：模拟 sherpa-onnx 默认行为（CIF 残余 alpha < 1.0 被丢弃）
- **有 tail_threshold=0.45**：在 CIF 积分末尾追加 0.45 alpha 强制 flush 残余 token

支持的 encoder 精度配置：
| 配置 | Encoder | Decoder | 说明 |
|------|---------|---------|------|
| int8 | encoder.int8.onnx | decoder.int8.onnx | sherpa-onnx 原始模型 |
| fp32-enc | encoder.onnx (fp32) | decoder.int8.onnx | 仅替换 encoder |
| fp32-all | encoder.onnx (fp32) | decoder.onnx (fp32) | 全 fp32 |
| fp16-all | encoder.fp16.ort.onnx | decoder.fp16.onnx | 全 fp16 (ORT_ENABLE_EXTENDED) |

## 测试用例

| ID | 音频 | 期望尾部关键词 | 完整期望文本 |
|----|------|----------------|-------------|
| cs_edge_008 | codeswitching/cs_edge_008.wav | "test" | CI pipeline跑了30分钟，还没通过unit test。 |
| wenet_net_001 | wenetspeech/wenet_net_001.wav | "觉" | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 |
| ascend_cs_003 | ascend/ascend_cs_003.wav | "opportunity" | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 |

## 验证结论

### 核心发现：int8 量化导致 ascend_cs_003 精度丢失

| ID | int8 (no/fix) | fp32 (no/fix) | fp16 (no/fix) |
|----|:---:|:---:|:---:|
| cs_edge_008 | ✓/✓ | ✓/✓ | ✓/✓ |
| wenet_net_001 | ✓/✓ | ✓/✓ | ✓/✓ |
| ascend_cs_003 | **✗/✗** | ✓/✓ | ✓/✓ |

- **cs_edge_008 和 wenet_net_001**：在离线全量推理模式下，三种精度都能完整识别尾部 token。说明这两条的截断**并非 encoder 精度问题**，而是 sherpa-onnx 流式 chunk 调度的问题。
- **ascend_cs_003**：int8 encoder 的 `alphas_sum` 偏差达 0.2492（int8=25.2679 vs fp32=25.0187），导致 CIF 积分错误，"opportunity" 的 BPE 子词 `[ity]` 永远无法被 fire，即使加 `tail_threshold` 也无法恢复。fp32 和 fp16 均完整输出。

### Alpha 精度对比

| 配置 | ascend_cs_003 alphas_sum | 与 fp32 的差值 |
|------|:---:|:---:|
| fp32-all | 25.0187 | 基准 |
| fp16-all | 25.0184 | 0.0003 |
| int8 | 25.2679 | **0.2492** |

fp16 与 fp32 的差异仅 0.0003，完全可忽略；int8 差异达 0.2492，足以在 CIF 积分中丢失 1-2 个 token。

### 模型大小对比

| 配置 | Encoder | Decoder | 总计 |
|------|:---:|:---:|:---:|
| int8 | 158 MB | 68 MB | **226 MB** |
| fp16 | 305 MB | 109 MB | **414 MB** |
| fp32 | 607 MB | 218 MB | **825 MB** |

## 启发

1. **int8 量化的 W8A8 方案（DynamicQuantizeLinear + MatMulInteger）在 200 层累积下产生不可忽略的精度损失**。虽然 weight dequantization 回到 fp32 后再做后续运算，但 uint8×uint8 乘法本身的精度损失已经在 CIF alphas 中体现。

2. **fp16 是最佳精度/大小权衡**：与 fp32 精度几乎一致（alphas_sum 差值 0.0003），体积仅为 fp32 的一半（414MB vs 825MB）。但需要注意 fp16 模型在 ONNX Runtime 中需要使用 `ORT_ENABLE_EXTENDED`（而非 `ORT_ENABLE_ALL`），否则 `SimplifiedLayerNormFusion` 优化会导致加载失败。

3. **CIF `tail_threshold` 在离线推理中作用有限**：如果 encoder 本身已经正确提取了 alpha 信息（如 fp32/fp16），尾部 token 在离线全量推理中通常不会丢失。`tail_threshold` 主要在流式场景下才有价值——用于 flush 最后一个 chunk 的残余 alpha。

4. **2/3 的截断问题根因在流式 chunk 调度**（cs_edge_008, wenet_net_001），而非 encoder 精度。这指向了 sherpa-onnx 的 IsReady() 门控、右上下文 alpha 零化和 CIF 无 final flush 三个流式特有问题。

## 依赖

```bash
uv run --with onnxruntime --with kaldi-native-fbank --with soundfile \
    python3 scripts/verify_onnx_tail_fix.py
```

需要预先下载 fp32/fp16 模型到 `/tmp/paraformer-fp32/` 目录。
