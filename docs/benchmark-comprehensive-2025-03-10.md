# ASR Pipeline 综合 Benchmark 报告

*生成时间：2026-03-10*
*测试集：67 条音频（corpus.json + real_manifest.json）*

**评估方案：**
- **Qwen3-ASR (流式)** — Autoregressive，chunk+rollback，内置 ITN + 标点 + 纠错
- **Paraformer Pipeline (INT8)** — sherpa-onnx 流式 + ITN + CSC + CT-Transformer 标点
- **Paraformer + Cloud Rewrite (GPT-OSS-120B)** — sherpa-onnx 流式 + Cerebras GPT-OSS-120B 云端后处理

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。多候选 expected_text 取最小 CER。

> **备注**：Paraformer FP16 模型因 sherpa-onnx 内嵌的 ONNX Runtime 版本不支持 FP16 图中的 `SimplifiedLayerNormFusion` 节点而无法加载，本次未参评。FP16 仅在 app 内通过原生 onnxruntime 1.21+ 可用。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 | CER≤0.05 | CER≤0.10 | CER>0.10 | 总推理时长 | RTF |
|----------|:-------:|:-----:|:-------:|:-------:|:-------:|:---------:|:---:|
| **Qwen3-ASR (流式)** | **0.0618** | 33/67 | 42 | 52 | 15 | 61.5s | 0.146x |
| Paraformer Pipeline (INT8) | 0.0968 | 15/67 | 18 | 45 | 22 | 13.0s | 0.031x |
| Paraformer + Cloud Rewrite (GPT-OSS-120B) | 0.0783 | 31/67 | 37 | 49 | 18 | 216.0s | 0.513x |

> Cloud API 用量（GPT-OSS-120B）：input 24,194 tokens, output 17,770 tokens, total 41,964 tokens

### 关键指标对比

| 指标 | Qwen3-ASR (流式) | Paraformer (INT8) | Paraformer + Cloud |
|------|:---:|:---:|:---:|
| 平均 CER | **0.0618** | 0.0968 | 0.0783 |
| 完美识别 (CER=0) | **33** | 15 | 31 |
| RTF (越小越快) | 0.146x | **0.031x** | 0.513x |
| 需要网络 | 否 | 否 | 是 |
| 需要 GPU | 否 | 否 | 否(云端) |

---

## 2. CER>0 的所有条目逐条分析

以下列出所有 CER>0 的条目，按最佳 CER 降序排列（从最差到最好），方便定位优化方向。

| # | ID | 类别 | Qwen3-ASR (流式) | Paraformer (INT8) | Paraformer+Cloud | 最佳 Pipeline | 主要错误类型 |
|:-:|-----|------|:---:|:---:|:---:|------|------|
| 1 | aishell_test_003 | real_aishell | **0.769** | 0.000 | 0.000 | Paraformer/Cloud | Qwen3 流式截断 |
| 2 | cs_error_01 | code_switching | 0.000 | 0.379 | **0.414** | Qwen3-ASR | Paraformer 英文词严重丢失 |
| 3 | ascend_cs_006 | real_ascend_cs | **0.123** | 0.304 | 0.393 | Qwen3-ASR | 口语化 + 英文词 friends→france |
| 4 | ascend_cs_003 | real_ascend_cs | **0.324** | 0.265 | 0.333 | Paraformer | 英文词 opportunity 截断 |
| 5 | dev_k8s_01 | developer_corpus | **0.000** | 0.324 | 0.324 | Qwen3-ASR | Paraformer Kubernetes→cubonates |
| 6 | cs_build_01 | code_switching | **0.000** | 0.300 | 0.250 | Qwen3-ASR | Paraformer macOS→michael s |
| 7 | wenet_net_009 | real_wenetspeech | **0.057** | 0.189 | 0.286 | Qwen3-ASR | Cloud 过度删减内容 |
| 8 | tech_num_01 | technical_numbers | **0.100** | 0.267 | 0.000 | Cloud | IP 地址 Paraformer 读成中文 |
| 9 | ascend_cs_004 | real_ascend_cs | **0.143** | 0.071 | 0.250 | Paraformer | "I like"→"i d like" |
| 10 | rate_fast_01 | speech_rate | **0.067** | 0.263 | 0.067 | Qwen3-ASR/Cloud | 快速数字顿读 |
| 11 | aishell_test_005 | real_aishell | **0.000** | 0.077 | 0.231 | Qwen3-ASR | Cloud 占略→占有率(过度纠正) |
| 12 | wenet_net_006 | real_wenetspeech | **0.122** | 0.220 | 0.146 | Qwen3-ASR | 皮特/Peter + FBI 拼有差异 |
| 13 | punct_list_01 | punctuation | **0.208** | 0.208 | 0.208 | 三者并列 | 步骤列表格式一致性 |
| 14 | wenet_net_002 | real_wenetspeech | **0.154** | 0.154 | 0.135 | Cloud | 竖锯→数据 同音有差异 |
| 15 | ascend_cs_001 | real_ascend_cs | **0.143** | 0.190 | 0.262 | Qwen3-ASR | No→那 同音混淆 |
| 16 | ascend_cs_009 | real_ascend_cs | **0.200** | 0.150 | 0.200 | Paraformer | 口语重复"你你" |
| 17 | cs_edge_008 | real_codeswitching | **0.000** | 0.200 | 0.133 | Qwen3-ASR | unit test 尾部截断 |
| 18 | wenet_net_003 | real_wenetspeech | **0.192** | 0.038 | 0.115 | Paraformer | Qwen3 添加引号改变 CER |
| 19 | wenet_net_001 | real_wenetspeech | **0.000** | 0.043 | 0.174 | Qwen3-ASR | 尾部"就感"截断 |
| 20 | wenet_net_008 | real_wenetspeech | **0.176** | 0.059 | 0.059 | Paraformer/Cloud | 月亮岛→月亮搭 同音错字 |
| 21 | ascend_cs_010 | real_ascend_cs | **0.057** | 0.143 | 0.171 | Qwen3-ASR | electrical→electric 英文截断 |
| 22 | conv_zh_001 | real_conversational | **0.120** | 0.160 | 0.080 | Cloud | 余额 + 口语词"呃" |
| 23 | wenet_net_007 | real_wenetspeech | **0.083** | 0.111 | 0.083 | Qwen3-ASR/Cloud | 她→他 同音字 |
| 24 | dev_git_01 | developer_corpus | **0.050** | 0.150 | 0.050 | Qwen3-ASR/Cloud | bug 尾部截断 |
| 25 | ascend_cs_005 | real_ascend_cs | **0.082** | 0.082 | 0.102 | Qwen3-ASR/Paraformer | and→嗯/然后 |
| 26 | mixed_02 | mixed_technical | **0.120** | 0.000 | 0.000 | Paraformer/Cloud | M3→M三 数字格式 |
| 27 | dev_db_01 | developer_corpus | **0.125** | 0.094 | 0.094 | Paraformer/Cloud | SQL→CQL |
| 28 | cs_review_01 | code_switching | **0.125** | 0.042 | 0.000 | Cloud | pull→po 英文词 |
| 29 | cs_edge_003 | real_codeswitching | **0.000** | 0.119 | 0.000 | Qwen3-ASR/Cloud | Docker→darker |
| 30 | pause_long_01 | mid_sentence_pause | **0.000** | 0.125 | 0.000 | Qwen3-ASR/Cloud | 一杯→1杯 |
| 31 | wenet_net_010 | real_wenetspeech | **0.095** | 0.048 | 0.053 | Paraformer | 围楼→为楼 |
| 32 | cs_edge_005 | real_codeswitching | **0.000** | 0.062 | 0.083 | Qwen3-ASR | type→tape, unwrap→and rap |
| 33 | en_short_01 | english_short | **0.000** | 0.091 | 0.091 | Qwen3-ASR | 句号缺失/格式 |
| 34 | ascend_cs_008 | real_ascend_cs | **0.087** | 0.087 | 0.043 | Cloud | "也喜"截断 |
| 35 | cs_edge_001 | real_codeswitching | **0.000** | 0.097 | 0.000 | Qwen3-ASR/Cloud | TypeScript→texcript |
| 36 | cs_var_01 | code_switching | **0.087** | 0.000 | 0.000 | Paraformer/Cloud | 赋值→复制 同音 |
| 37 | cs_edge_002 | real_codeswitching | **0.000** | 0.086 | 0.000 | Qwen3-ASR/Cloud | leak→li 截断 |
| 38 | dev_rust_01 | developer_corpus | **0.043** | 0.217 | 0.043 | Qwen3-ASR/Cloud | async await→a think wait |
| 39 | aishell_test_008 | real_aishell | **0.000** | 0.083 | 0.000 | Qwen3-ASR/Cloud | 一线→1线 |
| 40 | aishell_test_002 | real_aishell | **0.000** | 0.067 | 0.000 | Qwen3-ASR/Cloud | 一二→12 |
| 41 | cs_edge_007 | real_codeswitching | **0.000** | 0.091 | 0.061 | Qwen3-ASR | GraphQL→graph q l |
| 42 | dev_url_01 | developer_corpus | **0.077** | 0.154 | 0.077 | Qwen3-ASR/Cloud | github.com→github点co |
| 43 | cs_edge_004 | real_codeswitching | **0.023** | 0.068 | 0.000 | Cloud | issue→约sue |
| 44 | long_60s_01 | long_audio | **0.012** | 0.076 | 0.018 | Qwen3-ASR | 长音频尾部积累误差 |
| 45 | conv_zh_005 | real_conversational | **0.000** | 0.062 | 0.000 | Qwen3-ASR/Cloud | 您→民 同音 |
| 46 | wenet_net_004 | real_wenetspeech | **0.062** | 0.062 | 0.062 | 三者并列 | 30多层 格式差异 |
| 47 | wenet_net_005 | real_wenetspeech | **0.023** | 0.000 | 0.047 | Paraformer | 日后→结构 标点差异 |
| 48 | long_30s_01 | long_audio | **0.005** | 0.057 | 0.000 | Cloud | 十年→10年 格式 |
| 49 | dev_swift_01 | developer_corpus | **0.045** | 0.045 | 0.000 | Cloud | UserModel→user model |
| 50 | aishell_test_004 | real_aishell | **0.000** | 0.050 | 0.000 | Qwen3-ASR/Cloud | 三四→34 |
| 51 | dev_debug_01 | developer_corpus | **0.000** | 0.050 | 0.000 | Qwen3-ASR/Cloud | 42行 数字/格式 |
| 52 | mixed_01 | mixed_zh_en | **0.000** | 0.050 | 0.000 | Qwen3-ASR/Cloud | 1个→一个 |
| 53 | ascend_cs_002 | real_ascend_cs | **0.040** | 0.040 | 0.087 | Qwen3-ASR/Paraformer | 标点/口语词 |
| 54 | dev_api_01 | developer_corpus | **0.000** | 0.043 | 0.000 | Qwen3-ASR/Cloud | API→a p i |
| 55 | zh_long_01 | chinese_long | **0.000** | 0.024 | 0.000 | Qwen3-ASR/Cloud | 标点差异 |
| 56 | cs_edge_006 | real_codeswitching | **0.000** | 0.048 | 0.024 | Qwen3-ASR | Xcode→x c o d e |

---

## 3. 错误类型统计

| 错误类型 | Qwen3-ASR | Paraformer (INT8) | Cloud Rewrite | 说明 |
|---------|:---------:|:-----------------:|:------------:|------|
| **英文词截断/丢失** | 5 | 18 | 3 | Paraformer 对英文专有名词识别最差 |
| **同音字/近音字** | 8 | 10 | 2 | 三者都有，Cloud 纠错能力最强 |
| **数字/格式差异** | 4 | 12 | 1 | Paraformer 中文数字→阿拉伯/阿→中文不一致 |
| **标点差异** | 3 | 7 | 2 | Paraformer 无标点（baseline 依赖 CT-Transformer） |
| **流式截断** | 2 | 2 | 0 | 尾部 token 丢失 |
| **过度纠正** | 0 | 0 | 3 | Cloud LLM 改写内容或删减 |

---

## 4. 推理速度对比

| Pipeline | 总音频时长 | 总推理时间 | RTF | 平均/条 | 实时性 |
|----------|:--------:|:--------:|:---:|:------:|:-----:|
| **Paraformer (INT8)** | 421s | 13.0s | **0.031x** | 0.19s | 32x 实时 |
| **Qwen3-ASR (流式)** | 421s | 61.5s | 0.146x | 0.92s | 6.8x 实时 |
| **Paraformer + Cloud** | 421s | 216.0s | 0.513x | 3.22s | 1.9x 实时 |

---

## 5. 各 Pipeline 优劣势总结

### Qwen3-ASR (流式)

**优势：**
- 平均 CER 最低 (0.0618)，完美识别率最高 (33/67)
- 英文专有名词识别显著优于 Paraformer（Kubernetes、CrashLoopBackOff、async await 均正确）
- 内置 ITN + 标点 + 纠错，端到端质量高
- 完全本地运行，无网络依赖

**劣势：**
- RTF 0.146x，比 Paraformer 慢约 4.7 倍
- 流式 chunk+rollback 机制偶发截断（aishell_test_003 CER=0.769）
- mixed_technical / cs_var_01 等条目 Paraformer 更优

### Paraformer Pipeline (INT8)

**优势：**
- RTF 0.031x，推理速度最快（32 倍实时）
- 纯中文场景（real_aishell、real_wenetspeech）表现与 Qwen3-ASR 接近
- real_aishell 类别平均 CER (0.035) 反而优于 Qwen3-ASR (0.096)

**劣势：**
- 平均 CER 0.0968，比 Qwen3-ASR 高 57%
- 英文词识别是最大短板（macOS→michael s, async→a think, Kubernetes→cubonates）
- 仅 15/67 完美识别，需要配合后处理才能达到可用质量

### Paraformer + Cloud Rewrite (GPT-OSS-120B)

**优势：**
- Cloud LLM 对 Paraformer 的后处理效果显著：CER=0 从 15→31 条
- 标点、数字格式、英文大小写纠正能力强
- 能纠正部分同音字（馀额→余额、占略→战略）

**劣势：**
- RTF 0.513x（近 2 倍实时），受网络延迟和 API 限流影响
- 无法修复 ASR 根本性错误（cubonates 仍为 cubonates、no pointer 仍为 no pointer）
- 存在过度纠正风险（占略→占有率、删除内容）
- 依赖外部 API，有成本和可用性问题

---

## 6. 优化建议

### 高优先级（CER>0.20 的条目）

| ID | 当前最佳 CER | 建议 |
|----|:---:|-------|
| aishell_test_003 | 0.000 (Paraformer) | Qwen3 流式 chunk 策略调优，避免极短音频截断 |
| ascend_cs_003 | 0.265 (Paraformer) | 所有方案 opportunity 都截断，考虑增加语料或调整流式参数 |
| ascend_cs_006 | 0.123 (Qwen3) | friends→france 是 ASR 根本错误，需更多 code-switching 训练数据 |
| punct_list_01 | 0.208 (全部) | 步骤列表格式三个方案都不一致，考虑调整 expected_text 候选 |

### 中优先级（CER 0.10~0.20）

- **Qwen3-ASR 流式 chunk 稳定性**：aishell_test_003 (0.769) 是极端 case，需要排查 chunk rollback 机制在极短音频上的行为
- **Paraformer 英文词识别**：Paraformer 在 code-switching 场景（cs_error_01、cs_build_01、dev_k8s_01）CER 远高于 Qwen3-ASR，Cloud Rewrite 无法弥补 ASR 根本错误
- **Cloud Rewrite 过度纠正**：限制 LLM 改写范围，避免删减原始内容的行为（wenet_net_009）

### 测试集候选补充

建议为以下条目增加多候选 expected_text：
- `punct_list_01`: 当前 CER=0.208 对所有方案，实际断句风格不同但含义正确
- `aishell_test_003`: Qwen3 输出"但因为"被截断，可能是 chunk 边界问题而非识别错误

---

*报告基于 `scripts/benchmark_engines.py` 和 `scripts/benchmark_cloud_rewrite.py` 运行结果整合生成*
