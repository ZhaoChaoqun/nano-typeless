# ASR Pipeline 量化对比评估报告

*生成时间：2026-03-02 11:33*
*测试集：1 条音频（corpus.json + real_manifest.json）*
*Pipeline：Paraformer Pipeline*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer Pipeline | 0.2647 | 0/1 | 0 | 0 | 1 | 0.2s | 0.036x |

## 2. 按数据集/类别的平均 CER

| 类别 | N | Paraformer Pip | 最佳 |
|------|:-:|:------:|------|
| real_ascend_codeswitching | 1 | **0.265** | Paraformer Pip |
| **OVERALL** | 1 | **0.2647** | **Paraformer Pip** |

## 3. 逐条 CER 对比

| ID | 类别 | Paraformer | 最佳 |
|-----|------|:-----:|------|
| ascend_cs_003 | real_ascend_codeswitching | **0.265** | Paraformer |

## 4. 推理速度对比

| Pipeline | 总音频 | 总推理 | RTF | 平均/条 |
|----------|:-----:|:-----:|:---:|:------:|
| Paraformer Pipeline | 5s | 0.2s | 0.036x | 0.16s |

## 5. 各 Pipeline 识别错误案例详细分析

### 5.1 Paraformer Pipeline（1 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | ascend_cs_003 | 0.265 | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 | 深圳啊，或者是上海这种表达城市会有更opportun。 | 英文词丢失: opportunity |
深圳啊，或者上海这种比较大的城市，会有更多的 opportunity。深圳啊，或者上海这种比较大的城市，会有更多的 opportunity。深圳或者上海这种比较大的城市会有更多的opportunity。深圳或者上海这种比较大的城市会有更多的opportunity。
深圳或者上海这种深圳或者上海这种比较大的城市会有更多的opportunity。
## 6. 综合分析与建议

### 各场景最佳 Pipeline 推荐

| 场景 | 推荐 Pipeline | CER |
|------|--------------|:---:|
| real_ascend_codeswitching | Paraformer Pipeline | 0.265 |

### Pipeline 特点总结

**Paraformer Pipeline**
- 平均 CER: 0.2647
- 完美识别 (CER=0): 0/1 条
- 不准确 (CER>5%): 1/1 条
- RTF: 0.036x

---

*报告由 `scripts/benchmark_engines.py` 自动生成*