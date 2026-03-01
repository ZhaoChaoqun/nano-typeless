# 2025/2026 主流 ASR 模型调研报告

> 调研日期: 2025-02
> 重点关注: 中文普通话支持、中英混合识别、智能特性
> 目的: 为 Typeless 项目评估和选型 ASR 模型

---

## 目录

- [一、调研背景与关注维度](#一调研背景与关注维度)
- [二、开源模型](#二开源模型)
  - [2.1 OpenAI Whisper](#21-openai-whisper)
  - [2.2 Qwen3-ASR (阿里)](#22-qwen3-asr-阿里)
  - [2.3 SenseVoice (阿里 FunASR)](#23-sensevoice-阿里-funasr)
  - [2.4 FunASR Paraformer (阿里)](#24-funasr-paraformer-阿里)
  - [2.5 FireRedASR (小红书)](#25-fireredasr-小红书)
  - [2.6 Qwen2-Audio (阿里)](#26-qwen2-audio-阿里)
  - [2.7 Qwen2.5-Omni (阿里)](#27-qwen25-omni-阿里)
  - [2.8 PaddleSpeech (百度)](#28-paddlespeech-百度)
  - [2.9 WeNet](#29-wenet)
  - [2.10 sherpa-onnx (K2/Icefall)](#210-sherpa-onnx-k2icefall)
  - [2.11 NVIDIA Canary / Parakeet](#211-nvidia-canary--parakeet)
  - [2.12 Meta SeamlessM4T / MMS](#212-meta-seamlessm4t--mms)
  - [2.13 MiniCPM-o (面壁智能)](#213-minicpm-o-面壁智能)
  - [2.14 Moonshine (Useful Sensors)](#214-moonshine-useful-sensors)
  - [2.15 SpeechBrain](#215-speechbrain)
- [三、商业 API 服务](#三商业-api-服务)
  - [3.1 OpenAI GPT-4o-transcribe](#31-openai-gpt-4o-transcribe)
  - [3.2 Google Chirp / Gemini](#32-google-chirp--gemini)
  - [3.3 Microsoft Azure Speech](#33-microsoft-azure-speech)
  - [3.4 科大讯飞](#34-科大讯飞)
  - [3.5 腾讯云 ASR](#35-腾讯云-asr)
  - [3.6 字节跳动 Seed-ASR / 豆包](#36-字节跳动-seed-asr--豆包)
  - [3.7 Deepgram Nova](#37-deepgram-nova)
  - [3.8 AssemblyAI Universal-2](#38-assemblyai-universal-2)
  - [3.9 Amazon Transcribe](#39-amazon-transcribe)
- [四、中文 ASR 性能基准对比](#四中文-asr-性能基准对比)
- [五、用户关注的智能特性深度分析](#五用户关注的智能特性深度分析)
  - [5.1 口语化处理（去填充词/口癖）](#51-口语化处理去填充词口癖)
  - [5.2 专业术语识别](#52-专业术语识别)
  - [5.3 数字智能识别](#53-数字智能识别)
  - [5.4 软件工程术语识别](#54-软件工程术语识别)
  - [5.5 自定义热词 (Hotword)](#55-自定义热词-hotword)
  - [5.6 标点恢复](#56-标点恢复)
  - [5.7 逆文本正则化 (ITN)](#57-逆文本正则化-itn)
- [六、ASR + LLM 集成趋势](#六asr--llm-集成趋势)
  - [6.1 四种架构范式](#61-四种架构范式)
  - [6.2 端到端语音大模型](#62-端到端语音大模型)
  - [6.3 LLM 后处理纠错](#63-llm-后处理纠错)
  - [6.4 传统方案 vs LLM 方案对比](#64-传统方案-vs-llm-方案对比)
- [七、2025 年行业趋势](#七2025-年行业趋势)
- [八、Typeless 项目选型建议](#八typeless-项目选型建议)
- [九、信息来源](#九信息来源)

---

## 一、调研背景与关注维度

Typeless 是一款面向开发者的 macOS 语音输入法助手，当前使用 sherpa-onnx 框架进行端侧 ASR。本次调研重点评估以下维度：

| 维度 | 说明 |
|------|------|
| 中文精度 | AISHELL-1/2, WenetSpeech 等基准上的 CER |
| 中英混合 | 代码切换 (code-switching) 能力 |
| 口语化处理 | 自动过滤"嗯""啊""这个"等填充词 |
| 专业术语 | "Macbook Pro M4 芯片" 不会被识别为"M四芯片" |
| 数字识别 | "幺九二" → "192"，"幺三八" → "138" |
| 软件术语 | Kubernetes, MySQL, Docker, PostgreSQL, nginx 等 |
| 热词支持 | 自定义词汇表提升识别率 |
| 端侧部署 | 是否支持本地离线运行，资源消耗 |
| 流式识别 | 是否支持实时逐字输出 |

---

## 二、开源模型

### 2.1 OpenAI Whisper

| 项目 | 详情 |
|------|------|
| 最新版本 | v20250625, large-v3 (2023), turbo (2024) |
| 架构 | Transformer Encoder-Decoder (seq2seq) |
| 参数量 | tiny 39M / base 74M / small 244M / medium 769M / large-v3 1550M / turbo 809M |
| 语言数 | ~100 种 |
| 许可证 | MIT |
| 本地部署 | 支持 |
| 流式 | 不原生支持（非流式架构） |

**中文性能:**

| 基准 | CER (%) |
|------|---------|
| AISHELL-1 | 5.14 |
| AISHELL-2 | 4.96 |
| WenetSpeech Net | 10.48 |
| WenetSpeech Meeting | 18.87 |

**Turbo 变体 (2024):** 编码器保持 large-v3 不变，解码器从 32 层降至 4 层。模型大小从 ~6GB 降至 ~1.5GB，速度超越 tiny，精度接近 large-v2。但中文/CJK 语言有退化报告。

**智能特性:** 自动标点 ✓ | 热词 ✗ | ITN 有限 | 口癖过滤 ✗ | 流式 ✗

**评价:** 中文 ASR 领域使用最广泛的基线模型，但中文精度已被国产模型全面超越。主要价值在于多语言泛用性和丰富的社区生态。

---

### 2.2 Qwen3-ASR (阿里)

| 项目 | 详情 |
|------|------|
| 发布时间 | 2025 年 |
| 架构 | 基于 Qwen3-Omni 音频编码器 + LLM 解码器 |
| 参数量 | 1.7B / 0.6B |
| 语言数 | 30 种语言 + **22 种中文方言** (共 52 种) |
| 许可证 | Apache 2.0 |
| 本地部署 | 支持 |
| 流式 | **支持** (流式+离线统一模型) |

**中文方言覆盖:** 安徽、东北、福建、甘肃、四川、浙江、粤语(港/粤)、吴语、闽南语等 22 种方言。

**中文性能:**

| 基准 | 1.7B (WER%) | 0.6B (WER%) | Whisper-large-v3 |
|------|-------------|-------------|-------------------|
| AISHELL-2 | 2.71 | 3.15 | 5.06 |
| WenetSpeech Net | 4.97 | - | 9.86 |
| WenetSpeech Meeting | 5.88 | - | 19.11 |

**关键特性:**
- 流式 + 离线统一模型（开创性设计）
- 长音频转写支持
- 歌唱识别
- 强制对齐时间戳（ForcedAligner-0.6B）
- 0.6B 版并发 128 时吞吐量达 2000 倍实时

**智能特性:** 自动标点 ✓ | 热词 未知 | ITN 未知 | 口癖过滤 未知 | 流式 ✓

**评价:** 2025 年开源 ASR 模型的新 SOTA。22 种中文方言支持是重大差异化优势，流式+离线统一架构非常适合 Typeless 场景。

---

### 2.3 SenseVoice (阿里 FunASR)

| 项目 | 详情 |
|------|------|
| 架构 | 非自回归端到端 |
| 参数量 | Small ~234M / Large ~1.6B |
| 语言数 | 50+ (主力: 中/英/粤/日/韩) |
| 训练数据 | 40 万+ 小时 |
| 许可证 | 模型协议 (FunASR MIT) |
| 本地部署 | 支持 |
| 流式 | **不支持** |

**中文性能:**

| 基准 | SenseVoice-L CER(%) | Whisper-large-v3 |
|------|---------------------|-------------------|
| AISHELL-1 | 2.09 | 5.14 |
| AISHELL-2 | 3.04 | 4.96 |
| WenetSpeech Net | 6.01 | 10.48 |
| WenetSpeech Meeting | 6.73 | 18.87 |

**核心优势:**
- **内置 ITN**: 通过 `<|withitn|>` / `<|woitn|>` token 控制，训练时就内置了 ITN 和标点恢复
- **极快推理**: 10 秒音频仅需 70ms，比 Whisper-Large 快 **15 倍**
- **多任务**: ASR + 情感识别 (7 种) + 音频事件检测 (BGM/笑声/掌声/咳嗽) + 语言识别
- **ONNX 导出**: 支持

**智能特性:** 自动标点 ✓ | 热词 ✗ | **ITN ✓ (原生)** | 口癖过滤 ✗ | 流式 ✗

**评价:** 轻量级端到端方案的标杆。原生 ITN 支持是独特优势（"二零二五年" → "2025年"），但不支持流式是硬伤。适合离线批量转写。

---

### 2.4 FunASR Paraformer (阿里)

| 项目 | 详情 |
|------|------|
| 架构 | 非自回归 Paraformer |
| 参数量 | 220M |
| 训练数据 | 6 万小时中文 |
| 许可证 | MIT (FunASR) |
| 本地部署 | 支持 |
| 流式 | **支持** (streaming 变体, 可配置 chunk_size) |

**中文性能:**

| 基准 | CER (%) |
|------|---------|
| AISHELL-1 | 1.68 |
| AISHELL-2 | 2.85 |
| WenetSpeech Net | 6.74 |
| WenetSpeech Meeting | 6.97 |

**核心优势:**
- **热词 (Hotword) 支持**: 通过 hotword 参数 + WFST 热词集成
- **流式识别**: Paraformer-zh-streaming，可配置延迟 (chunk_size)
- **标点恢复**: CT-Transformer 标点模型 (290M)，支持 INT8 量化
- **sherpa-onnx 集成**: Typeless 项目**当前正在使用**

**Fun-ASR-Nano-2512 (新):**
- 参数量 800M
- 支持: 中/英/日 + **7 种中文方言 + 26 种地区口音**
- 训练数据: 千万小时级别
- 支持歌词识别、说唱识别

**智能特性:** 自动标点 ✓ (ct-punc) | **热词 ✓** | ITN ✗ (需外部) | 口癖过滤 ✗ | **流式 ✓**

**评价:** 最成熟的开源中文 ASR 生产方案。热词 + 流式 + 标点的组合在开源方案中独一无二。220M 参数量适合端侧部署。

---

### 2.5 FireRedASR (小红书)

| 项目 | 详情 |
|------|------|
| 发布时间 | 2025 年 |
| 许可证 | Apache 2.0 |
| 论文 | arXiv:2501.14350 |

**两个变体:**

| 模型 | 参数量 | 架构 | 最大音频 |
|------|--------|------|----------|
| FireRedASR-AED | 1.1B | Attention-based Encoder-Decoder | 60 秒 |
| FireRedASR-LLM | 8.3B | Encoder-Adapter-LLM (基于 Qwen2-7B) | 30 秒 |

**中文性能 (CER%):**

| 模型 | AISHELL-1 | AISHELL-2 | WenetSpeech Net | WenetSpeech Meeting | 均值 |
|------|-----------|-----------|-----------------|---------------------|------|
| **FireRedASR-AED** | **0.55** | 2.52 | 4.88 | 4.76 | 3.18 |
| **FireRedASR-LLM** | 0.76 | **2.15** | **4.60** | **4.67** | **3.05** |
| Seed-ASR | 0.68 | 2.27 | 4.66 | 5.69 | 3.33 |
| Whisper-large-v3 | 5.14 | 4.96 | 10.48 | 18.87 | 9.86 |

**中文方言 KeSpeech:** AED 4.48% / LLM **3.56%** (前 SOTA 6.70%)

**限制:** 输入需 16kHz 16-bit PCM WAV；不支持流式；本地部署需较大 GPU (LLM 版)。

**智能特性:** 自动标点 未知 | 热词 ✗ | ITN 未知 | 口癖过滤 未知 | 流式 ✗

**评价:** 中文 ASR 精度的新标杆。AED 版 AISHELL-1 CER 0.55% 是目前已知最低。但参数量较大，不适合端侧部署。后续 FireRedASR2S 系统将集成 VAD + 语种识别 + 标点。

---

### 2.6 Qwen2-Audio (阿里)

| 项目 | 详情 |
|------|------|
| 架构 | 音频编码器 (Whisper-based) + Qwen2-7B LLM |
| 参数量 | ~7B |
| 许可证 | Apache 2.0 |
| 最佳音频长度 | < 30 秒 |
| 流式 | 不支持 |

**中文性能 (WER%):**
- AISHELL-2: 2.9-3.2%
- Fleurs-zh: 7.0%
- Common Voice-zh: 6.5%

**功能:** ASR + 翻译 + 情感识别 + 音频分类。多任务能力强但 ASR 精度不如专用模型 (AISHELL-1 CER ~1.30%)。

---

### 2.7 Qwen2.5-Omni (阿里)

| 项目 | 详情 |
|------|------|
| 发布时间 | 2025 年 3 月 |
| 架构 | Thinker-Talker (LLM + 双轨自回归音频解码器) |
| 特性 | 端到端多模态 (文本+图像+音频+视频输入，文本+语音输出) |
| 流式 | 支持 (Sliding-window DiT 降低首包延迟) |

**核心创新:**
- TMRoPE (Time-aligned Multimodal RoPE): 同步视频和音频时间戳
- Thinker 生成文本隐层表征 → Talker 流式生成音频 token
- 全双工语音交互

**评价:** 面向通用多模态对话的模型，ASR 只是其中一项能力。对 Typeless 参考价值有限。

---

### 2.8 PaddleSpeech (百度)

| 项目 | 详情 |
|------|------|
| 架构 | Conformer, U2/U2++, Squeezeformer |
| 许可证 | Apache 2.0 |
| 流式 | 支持 (WebSocket) |

**中文特性:**
- 命令行直接使用: `paddlespeech asr --lang zh`
- 中英混合: 支持 (Code-switch online model, 2025 年 8 月添加)
- 流式标点恢复: 内置
- ARM Linux / 嵌入式 C++ 支持

**评价:** 百度生态的开源 ASR 框架，功能较全但社区活跃度和模型更新速度不如阿里系方案。

---

### 2.9 WeNet

| 项目 | 详情 |
|------|------|
| 最新版本 | v3.1.0 (2024 年 5 月) |
| 架构 | Conformer/Transformer/Paraformer + WFST 解码 |
| 许可证 | Apache 2.0 |
| 设计理念 | "Production First" |

**中文模型选项:** paraformer, firered, wenetspeech 三种。统一流式+非流式架构，libtorch 跨平台 C++ runtime。

---

### 2.10 sherpa-onnx (K2/Icefall)

| 项目 | 详情 |
|------|------|
| 推理引擎 | ONNX Runtime |
| 许可证 | Apache 2.0 |
| 平台 | Android, iOS, Windows, macOS, Linux, HarmonyOS, WebAssembly, Raspberry Pi, NVIDIA Jetson |
| 编程语言 | 12 种 (C++, C, Python, JS, Java, C#, Kotlin, Swift, Go, Dart, Rust, Pascal) |
| NPU | Rockchip, Qualcomm, Ascend, Axera |

**中文模型:**
- **流式**: Zipformer bilingual zh-en, Streaming Paraformer, 14M 轻量模型
- **离线**: SenseVoice, Paraformer-zh, TeleSpeech CTC

**核心功能:** ASR + TTS + VAD + 说话人分离 + 关键词检测 + 标点 + 语音增强

**评价:** 边缘/移动端部署的最佳方案，Typeless 项目**当前正在使用**。跨平台覆盖最广，模型兼容性最强。

---

### 2.11 NVIDIA Canary / Parakeet

| 模型 | 参数量 | 语言 | 中文 |
|------|--------|------|------|
| Canary-1B | 1B | 英/德/法/西 | **不支持** |
| Canary-1B-Flash | 883M | 英/德/法/西 | **不支持** |
| Canary-1B-v2 | 1B | 25 种欧洲语言 | **不支持** |
| Parakeet-TDT-0.6B-v2 | 600M | 仅英文 | **不支持** |

**评价:** NVIDIA 所有预训练 ASR 模型均**不支持中文**。NeMo 框架支持自训练中文模型，但无开箱即用方案。

---

### 2.12 Meta SeamlessM4T / MMS

| 模型 | 参数量 | ASR 语言 | 中文 |
|------|--------|----------|------|
| SeamlessM4T v2 Large | 2.3B | ~100 | 含普通话 (实验性) |
| MMS | 300M / 1B | 最高 1162 | 含普通话 |

**许可证:** CC-BY-NC-4.0 (非商用)

**评价:** 面向多语言研究的模型。MMS 的语言覆盖最广 (1162 种)，但中文性能远不如专用模型。

---

### 2.13 MiniCPM-o (面壁智能)

| 项目 | 详情 |
|------|------|
| 架构 | 端到端 Omni-modal (模态编码器/解码器 + LLM) |
| 特性 | 中英双语实时语音交互 + 声音克隆 + 角色扮演 |
| 许可证 | 开源 |
| 部署 | llama.cpp, Ollama, vLLM, int4 量化 |

---

### 2.14 Moonshine (Useful Sensors)

| 项目 | 详情 |
|------|------|
| 定位 | 端侧专用 ASR |
| 参数量 | Moonshine Medium 245M |
| 特性 | C++ + OnnxRuntime, 按语言训练独立模型 |
| 流式 | 支持 |

**性能:** Moonshine Medium (245M) WER 6.65%，超越 Whisper Large v3 (1.5B) 的 7.44%，参数量仅 1/6。Moonshine Tiny 在 Raspberry Pi 5 上 237ms vs Whisper Tiny 5,863ms (**25x 加速**)。

**限制:** 目前仅支持英文。

---

### 2.15 SpeechBrain

PyTorch 训练工具包，200+ recipes，100+ 预训练模型。包含 AISHELL-1 中文 recipe，但主要是训练框架而非生产级预训练模型。Apache 2.0 许可。

---

## 三、商业 API 服务

### 3.1 OpenAI GPT-4o-transcribe

| 项目 | 详情 |
|------|------|
| 发布时间 | 2025 年 3 月 |
| 架构 | LLM-based ASR (GPT-4o 多模态能力) |
| 语言数 | ~50 种 (含中文) |
| 流式 | 支持 |
| 本地部署 | **不支持** (仅 API) |

**vs Whisper:** 利用 LLM 上下文理解能力，声称比 Whisper 更准确。AISHELL-2 WER 4.24%。

**评价:** OpenAI 的新一代 ASR API，LLM 原生架构带来更好的上下文理解和格式化输出。但仅限 API 调用，不适合本地部署场景。

---

### 3.2 Google Chirp / Gemini

**Chirp 3 (2025):** 基于 Universal Speech Model (USM)，100+ 语言，支持中文 (简体/繁体/粤语)，说话人分离。仅云 API。

**Gemini 多模态 ASR:**
- 音频处理: 32 tokens/秒，最长 9.5 小时
- 中文转写: 支持 (含说话人分离、情感检测)
- **限制**: 不支持实时转写
- **中文精度较差**: WenetSpeech-net WER 14.43%, meeting 13.47% (远不如专用 ASR)

---

### 3.3 Microsoft Azure Speech

| 项目 | 详情 |
|------|------|
| 中文支持 | zh-CN (简体), zh-TW (繁体), 粤语 |
| 本地部署 | **支持** (Docker 容器) |
| 流式 | 支持 |
| SDK | C#, C++, Python, Java, JavaScript, Swift, Go |

**核心优势:**
- **Phrase List (热词)**: 支持，权重可调 (0-2.0)
- **Custom Speech**: 领域自适应训练
- **说话人分离**: 最多 35 人
- **LLM Speech (Preview)**: 新一代 LLM 增强语音模型

**评价:** 企业级 ASR 的标杆方案。Docker 本地部署 + Custom Speech + Phrase List 的组合在商业服务中最灵活。

---

### 3.4 科大讯飞

| 项目 | 详情 |
|------|------|
| 准确率 | 宣称高达 98% |
| 方言 | 23 种 (四川/粤语/上海/闽南/客家/东北/河南/山东等) |
| 星火大模型 | 37 种外语 + **202 种方言**，自动语种/方言检测 |
| 私有化部署 | 支持 (商务) |
| 流式 | 支持 (毫秒级响应) |

**核心优势:**
- 方言覆盖最广
- **动态修正**: 流式返回中实时修正（仅中文）
- 自训练平台: 上传常用词句，无需算法开发
- 垂直领域优化: 政府、金融等

**价格:** 免费试用 1 万次，收费从 1300 元/50 万次起

---

### 3.5 腾讯云 ASR

| 项目 | 详情 |
|------|------|
| 语言 | 13 种 |
| 方言 | **24 种** (粤语/上海话/四川话/西安话等) |
| 三语引擎 | 普通话+粤语+英语同时识别 |
| 准确率 | 宣称 95%+ (输入法场景) |
| 流式 | 支持 (WebSocket) |

**核心优势:** 热词/自训练支持，HarmonyOS SDK 已推出。

**价格:** 新用户免费 5000 次一句话，收费约 72 元/30 小时。

---

### 3.6 字节跳动 Seed-ASR / 豆包

| 项目 | 详情 |
|------|------|
| 架构 | Audio conditioned LLM (AcLLM) |
| 参数量 | 12B+ |
| 开源 | **否** (仅论文) |

**中文性能 (CER%):**
- AISHELL-1: 0.68
- AISHELL-2: 2.27
- WenetSpeech Net: 4.66 / Meeting: 5.69

**核心特色:** 无需额外语言模型融合的上下文感知能力。声称中英文公开测试集上比其他大型 ASR 降低 10%-40% CER/WER。商业化通过字节旗下"豆包" ASR API 提供。

---

### 3.7 Deepgram Nova

**Nova-3 (2025):** 约 7 种语言，53.4% WER 降低 (streaming vs 竞品)。支持 disfluency 去除、即时词汇适应，但**当前不支持中文** (中文需用 Nova-2)。

**Nova-2 中文:** 支持简体/繁体/粤语，功能有限。仅云 API。

---

### 3.8 AssemblyAI Universal-2

600M Conformer RNN-T，1250 万小时多语言预训练。全神经网络文本格式化 (标点+大小写+ITN)。**中文支持不明确**，主要聚焦英文。仅 API。

---

### 3.9 Amazon Transcribe

支持简体/繁体/粤语。**重要限制**: 中文不支持数字转写、自定义词汇、自定义语言模型、PII 编辑功能。

---

## 四、中文 ASR 性能基准对比

### 综合 CER/WER 对比 (%)

| 模型 | 参数量 | AISHELL-1 | AISHELL-2 | WenetSpeech Net | WenetSpeech Meeting | 均值 | 流式 | 开源 |
|------|--------|-----------|-----------|-----------------|---------------------|------|------|------|
| **FireRedASR-AED** | 1.1B | **0.55** | 2.52 | 4.88 | 4.76 | 3.18 | ✗ | ✓ |
| **FireRedASR-LLM** | 8.3B | 0.76 | **2.15** | **4.60** | **4.67** | **3.05** | ✗ | ✓ |
| Seed-ASR | 12B+ | 0.68 | 2.27 | 4.66 | 5.69 | 3.33 | ? | ✗ |
| **Qwen3-ASR-1.7B** | 1.7B | ~SOTA | 2.71 | 4.97 | 5.88 | ~3.6 | **✓** | ✓ |
| **SenseVoice-L** | 1.6B | 2.09 | 3.04 | 6.01 | 6.73 | 4.47 | ✗ | ✓ |
| **Paraformer-Large** | 220M | 1.68 | 2.85 | 6.74 | 6.97 | 4.56 | **✓** | ✓ |
| Qwen-Audio | 8.4B | 1.30 | 3.10 | 9.50 | 10.87 | 6.19 | ✗ | ✓ |
| GPT-4o-transcribe | ? | - | 4.24 | - | - | - | ✓ | ✗ |
| Whisper-large-v3 | 1.6B | 5.14 | 4.96 | 10.48 | 18.87 | 9.86 | ✗ | ✓ |
| Gemini 2.5 Pro | ? | - | - | 14.43 | 13.47 | - | ✗ | ✗ |

### 中文方言 KeSpeech CER (%)

| 模型 | KeSpeech |
|------|----------|
| **FireRedASR-LLM** | **3.56** |
| FireRedASR-AED | 4.48 |
| 前 SOTA | 6.70 |

### 性能梯队总结

```
第一梯队 (CER 均值 < 3.5%):
  FireRedASR-LLM (3.05) > FireRedASR-AED (3.18) > Seed-ASR (3.33)

第二梯队 (CER 均值 3.5%-5%):
  Qwen3-ASR-1.7B (~3.6) > SenseVoice-L (4.47) > Paraformer-Large (4.56)

第三梯队 (CER 均值 > 5%):
  Qwen-Audio (6.19) > Whisper-large-v3 (9.86) > Gemini (13+)
```

---

## 五、用户关注的智能特性深度分析

### 5.1 口语化处理（去填充词/口癖）

**问题:** 用户说话时的"嗯""啊""这个""那个""就是说"等填充词影响转写质量。

| 方案 | 实现方式 | 效果 | 延迟 |
|------|---------|------|------|
| **传统规则过滤** | 基于规则 + CRF/BiLSTM 序列标注 | 常见口癖覆盖好，复杂情况差 | 极低 |
| **商业 API** | 讯飞 "动态修正"、Deepgram disfluency removal (仅英文) | 效果好 | 云端延迟 |
| **LLM 后处理** | ASR 输出 → LLM 清理 | 语义理解最准确 | 高 (需 LLM 推理) |
| **端到端模型** | SenseVoice 等训练时就包含填充词标注 | 部分模型支持 | 低 |

**现状:** 大多数开源 ASR 模型**不原生支持**口癖过滤。最实用的方案是：
1. ASR + 后置规则过滤（低延迟）
2. ASR + LLM 后处理（高质量但延迟大）

---

### 5.2 专业术语识别

**问题:** "Macbook Pro M4 芯片" 被识别为 "Macbook Pro M四芯片"。

| 方案 | 技术 | 模型支持 |
|------|------|---------|
| **热词/Contextual Biasing** | WFST boosting / attention-based bias | FunASR Paraformer, Azure Phrase List, 讯飞自训练, 腾讯热词 |
| **LLM 纠错** | ASR N-best → LLM 选择/生成 | 任何 ASR + LLM |
| **自定义训练** | 使用领域数据微调 | Azure Custom Speech, 讯飞自训练平台 |
| **大规模预训练** | 训练数据本身覆盖 | Seed-ASR, FireRedASR-LLM (利用 LLM 世界知识) |

**最佳实践:** 热词机制是核心方案。FunASR 的 hotword 参数是开源方案中最成熟的实现。

---

### 5.3 数字智能识别

**问题:** "幺九二" → "192"，"幺三八" → "138"，电话号码、IP 地址等。

| 方案 | 技术 | 说明 |
|------|------|------|
| **WFST / 规则 ITN** | Finite-State Transducer 规则 | 精确可控，零延迟，确定性输出 |
| **SenseVoice 原生 ITN** | 训练时内置 `<\|withitn\|>` | 模型端到端处理，无需后处理 |
| **NeMo ITN** | NVIDIA 的规则化 ITN 框架 | 多语言规则覆盖 |
| **LLM 理解** | LLM 根据上下文判断格式 | 处理歧义更灵活 ("二零二五" vs "两千零二十五") |

**中文 ITN 特殊挑战:**

| 输入 | 期望输出 | 难点 |
|------|---------|------|
| "幺九二" | "192" | "幺" = 1 的口语表达 |
| "一百三十八" | "138" | 中文数字到阿拉伯数字 |
| "二零二五年三月" | "2025年3月" | 日期格式化 |
| "三千五百块" | "3500元" | 金额单位 |
| "百分之九十五" | "95%" | 百分比 |

**现状:** SenseVoice 的原生 ITN 是目前最优雅的开源方案。传统 WFST 规则在覆盖"幺九二"等非标准表达上需要大量手工规则。

---

### 5.4 软件工程术语识别

**问题:** Kubernetes, MySQL, Docker, PostgreSQL, nginx, webpack 等专业词汇。

**挑战分析:**

| 术语 | 常见误识别 | 原因 |
|------|-----------|------|
| Kubernetes | "酷伯内特斯" | 音译匹配 |
| MySQL | "买思口" | 非标准发音 |
| PostgreSQL | "波斯特格瑞" | 长词音译 |
| nginx | "恩gin克斯" | 不规则发音 |
| webpack | "韦伯派克" | 复合词 |

**解决方案优先级:**
1. **热词表**: 维护一个软件工程术语热词列表（最直接）
2. **LLM 后处理**: ASR 输出 "酷伯内特斯" → LLM 纠正为 "Kubernetes"
3. **领域微调**: 使用软件工程领域的语料微调模型
4. **AcLLM 模型**: Seed-ASR, FireRedASR-LLM 等基于 LLM 的模型有更好的世界知识

**评价:** 目前没有任何模型针对软件工程场景做过专门的 fine-tuning。热词表 + LLM 后处理是最实用的组合方案。

---

### 5.5 自定义热词 (Hotword)

| 服务/模型 | 热词支持 | 方式 |
|-----------|---------|------|
| **FunASR Paraformer** | ✓ | hotword 参数 + WFST 集成 |
| **Azure Speech** | ✓ | Phrase List, 权重可调 (0-2.0) |
| **科大讯飞** | ✓ | 自训练平台上传 |
| **腾讯云 ASR** | ✓ | 热词列表上传 |
| **Deepgram Nova-3** | ✓ | 即时词汇适应 (无需重训练) |
| Whisper | ✗ | - |
| SenseVoice | ✗ | - |
| Qwen3-ASR | 未知 | - |
| FireRedASR | ✗ | - |

**结论:** 开源方案中只有 FunASR Paraformer 原生支持热词。

---

### 5.6 标点恢复

| 方案 | 模型/服务 | 延迟 |
|------|----------|------|
| SenseVoice 原生 | `<\|withitn\|>` token | 零额外延迟 |
| CT-Transformer | FunASR ct-punc (290M, INT8 可用) | ~ms 级 |
| LLM 后处理 | 任何 LLM | 较高 |
| Azure | 内置自动标点 | 云端延迟 |
| 讯飞 | 基于中文语境智能断句 | 云端延迟 |
| Chirp 3 | 所有版本支持 | 云端延迟 |

**评价:** 标点恢复已是多数方案的标配。CT-Transformer 是独立标点模型中最成熟的。

---

### 5.7 逆文本正则化 (ITN)

| 方案 | 说明 | 示例 |
|------|------|------|
| **SenseVoice 原生** | 训练时内置，`use_itn` 参数 | "二零二五年" → "2025年" |
| **WFST 规则** | 有限状态转换器 | 确定性转换 |
| **NeMo Text Processing** | NVIDIA 多语言 ITN | "两点五万" → "2.5万" |
| **LLM 后处理** | 自然语言指令 | 灵活但不确定 |

**现状:** SenseVoice 将 ITN 内嵌端到端训练是目前最佳实践。传统 WFST 规则维护成本高但确定性好。

---

## 六、ASR + LLM 集成趋势

### 6.1 四种架构范式

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 传统 Pipeline                                            │
│    音频 → ASR → 标点恢复 → ITN → [可选: LLM 纠错]           │
│    代表: Whisper + CT-Transformer + 规则 ITN                 │
│    优点: 模块化、可分别优化                                    │
│    缺点: 错误累积、延迟高                                     │
├─────────────────────────────────────────────────────────────┤
│ 2. Audio Conditioned LLM (AcLLM)                            │
│    音频 → 音频编码器 → LLM 解码器 → 文本                      │
│    代表: Seed-ASR, FireRedASR-LLM, Qwen3-ASR                │
│    优点: LLM 上下文理解、自动格式化/纠错                       │
│    缺点: 参数量大、资源消耗高                                  │
├─────────────────────────────────────────────────────────────┤
│ 3. 多模态大模型                                              │
│    音频 → 原生多模态 LLM → 文本/音频                          │
│    代表: GPT-4o, Gemini, Qwen2.5-Omni                       │
│    优点: 灵活、自然语言指令控制输出                             │
│    缺点: 延迟高、成本高、ASR 精度不如专用模型                   │
├─────────────────────────────────────────────────────────────┤
│ 4. 轻量级端到端                                              │
│    音频 → 非自回归模型 → 文本 (含标点/ITN)                    │
│    代表: SenseVoice, Paraformer                              │
│    优点: 速度快、资源低、适合边缘部署                          │
│    缺点: 缺乏 LLM 级别的上下文理解                            │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 端到端语音大模型

| 模型 | 架构 | 端到端 | 中文 | 开源 |
|------|------|--------|------|------|
| Qwen2.5-Omni | Thinker-Talker | ✓ | ✓ | ✓ |
| GPT-4o | 原生多模态 (未公开) | ✓ | ✓ | ✗ |
| Gemini | 原生多模态 (未公开) | ✓ | ✓ | ✗ |
| Seed-ASR | AcLLM | ✓ | ✓ | ✗ |
| SALMONN | 双编码器 + LLM | ✓ | ✓ | ✓ |
| WavLLM | Whisper + WavLM + LLM | ✓ | 有限 | ✓ |
| MiniCPM-o | Omni-modal + LLM | ✓ | ✓ | ✓ |

### 6.3 LLM 后处理纠错

**HyPoradise / 生成式错误纠正 (GER):**

ASR 系统产生 N-best 假设列表 → LLM 接收假设列表 → 生成式纠正输出。与传统 LM rescoring 仅能从候选中选择不同，GER 可以**生成不在候选列表中的正确 token**。

**效果评估 (WER 改善):**

| 数据集 | Baseline WER | 最佳 GER WER | 相对改善 |
|--------|-------------|-------------|---------|
| WSJ | 4.5% | 2.2% | **-51.1%** |
| ATIS | 8.3% | 1.7% | **-79.5%** |
| CHiME-4 | 11.1% | 6.6% | -40.5% |
| Tedlium-3 | 8.5% | 4.6% | -45.9% |

**关键发现:**
- LoRA 微调一致优于全量微调
- 传统 LM rescoring 仅提供边际增益 (-4.4%)，而生成式纠错可达 **-51.1%**
- **实时场景不适用**: 需要等待完整句子的 N-best 输出才能纠错
- **离线/批处理场景**: 非常有价值

**典型 Prompt 模式:**
```
你是一位语音识别后处理专家。以下是 ASR 输出的多个候选结果：
候选1: [hypothesis 1]
候选2: [hypothesis 2]
候选3: [hypothesis 3]
请输出最准确的转录结果。
```

**高级技巧:**
1. 提供领域上下文 (会议/医疗/金融等)
2. 在 prompt 中列出可能出现的专业术语
3. 给出前几句的正确转录作为上下文
4. Chain-of-Thought 要求解释纠正原因
5. 明确 ITN 格式约束

### 6.4 传统方案 vs LLM 方案对比

| 特性 | 传统方案 | LLM 方案 | 推荐 |
|------|---------|---------|------|
| **口癖过滤** | 规则+序列标注 (低延迟) | LLM 语义理解 (高延迟) | 实时: 传统; 离线: LLM |
| **术语识别** | 热词 boosting (实时) | LLM 世界知识 (高延迟) | 组合使用 |
| **数字转换** | WFST 规则 (精确) | LLM 上下文 (灵活) | 实时: 规则; 歧义: LLM |
| **热词** | Contextual biasing (声学层) | Prompt 列表 (语义层) | 声学: 传统; 补充: LLM |
| **标点** | CT-Transformer (~ms) | LLM (较高延迟) | 实时: CT-Trans; 高质量: LLM |
| **ITN** | SenseVoice 原生 / WFST | LLM 后处理 | SenseVoice 原生最优 |

---

## 七、2025 年行业趋势

### 7.1 AcLLM 架构成为主流

Seed-ASR、FireRedASR-LLM、Qwen3-ASR 均采用"音频编码器 + LLM 解码器"架构，在 AISHELL 等基准上取得 SOTA。LLM 的世界知识天然适合错误纠正和格式规范化。

### 7.2 流式+离线统一模型

Qwen3-ASR 开创性地用**单一模型同时支持流式和离线模式**，避免了维护两套模型的开销。

### 7.3 端侧 ASR 加速

- **模型压缩**: Moonshine 245M 超越 Whisper 1.5B; SenseVoice-Small 快 15 倍
- **硬件加速**: NPU (手机/嵌入式)、Neural Engine (Apple)、Hexagon (Qualcomm)
- **量化**: INT8 模型大幅降低内存和计算（SenseVoice INT8、CT-Transformer INT8）
- **框架**: sherpa-onnx 12 种语言 + 全平台覆盖

### 7.4 中文方言成为差异化竞争点

| 服务 | 方言数 |
|------|--------|
| 讯飞星火 | **202 种** |
| 腾讯云 | 24 种 |
| 讯飞标准版 | 23 种 |
| Qwen3-ASR | 22 种 |
| Fun-ASR-Nano | 7 种 + 26 种口音 |

### 7.5 Voice Agent 爆发

Gemini Live API、GPT-4o Realtime API 推动实时语音 AI Agent。全面从 ASR→LLM→TTS 管线式方案向端到端 Speech-to-Speech 进化。

### 7.6 端云协同

端侧处理实时转录 (Streaming Paraformer / SenseVoice-Small) + 可选的云端 LLM 做后处理优化，是中期最优架构。

---

## 八、Typeless 项目选型建议

### 当前方案

Typeless 使用 sherpa-onnx + Streaming Paraformer + CT-Transformer 标点。这是一个**成熟且实用的端侧方案**。

### 升级路径建议

#### 短期: 优化当前方案

| 改进 | 方案 | 收益 |
|------|------|------|
| **热词支持** | 利用 Paraformer 已有的 hotword 参数 | 术语识别大幅改善 |
| **软件术语热词表** | 维护 Kubernetes/MySQL/Docker 等热词 | 直接解决用户痛点 |
| **规则 ITN** | 添加"幺→1"等数字映射规则 | 数字识别改善 |
| **口癖过滤** | 后置规则过滤"嗯/啊/这个/那个" | 低成本改善 |

#### 中期: 模型升级

| 方案 | 模型 | 优势 | 注意事项 |
|------|------|------|---------|
| **方案 A** | Qwen3-ASR-0.6B (流式) | SOTA 精度 + 流式 + 22 方言 | 需评估端侧资源消耗 |
| **方案 B** | SenseVoice-Small (离线) | 原生 ITN + 极快推理 + 情感检测 | 不支持流式 |
| **方案 C** | Fun-ASR-Nano (7 方言) | 方言覆盖 + 千万小时训练 | 参数量 800M，需评估 |

#### 长期: 端云协同

| 层 | 方案 |
|----|------|
| **端侧** | sherpa-onnx + Qwen3-ASR-0.6B (流式) |
| **可选云端** | LLM 后处理纠错 (专业术语、格式规范化) |

### 功能优先级排序

| 优先级 | 功能 | 实现方案 |
|--------|------|---------|
| P0 | 热词 (软件术语) | Paraformer hotword 参数 |
| P0 | 基础 ITN (数字/日期) | 规则后处理 or SenseVoice |
| P1 | 口癖过滤 | 规则过滤 |
| P1 | 标点恢复 | CT-Transformer (已有) |
| P2 | 模型升级 | Qwen3-ASR-0.6B |
| P3 | LLM 纠错 | 可选云端 LLM |

---

## 九、信息来源

### 开源项目
- [OpenAI Whisper](https://github.com/openai/whisper)
- [FunASR](https://github.com/modelscope/FunASR)
- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice)
- [Qwen2-Audio](https://github.com/QwenLM/Qwen2-Audio)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)
- [FireRedASR](https://github.com/FireRedTeam/FireRedASR)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
- [WeNet](https://github.com/wenet-e2e/wenet)
- [PaddleSpeech](https://github.com/PaddlePaddle/PaddleSpeech)
- [SpeechBrain](https://github.com/speechbrain/speechbrain)
- [SeamlessM4T](https://github.com/facebookresearch/seamless_communication)
- [MMS](https://github.com/facebookresearch/fairseq/tree/main/examples/mms)
- [MiniCPM-o](https://github.com/OpenBMB/MiniCPM-o)
- [Moonshine](https://github.com/usefulsensors/moonshine)

### HuggingFace 模型
- [SenseVoice-Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)
- [NVIDIA Canary-1B](https://huggingface.co/nvidia/canary-1b)
- [NVIDIA Canary-1B-Flash](https://huggingface.co/nvidia/canary-1b-flash)
- [NVIDIA Parakeet-TDT-0.6B-v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)

### 论文
- [Seed-ASR (arXiv:2407.04675)](https://arxiv.org/abs/2407.04675)
- [FireRedASR (arXiv:2501.14350)](https://arxiv.org/abs/2501.14350)
- [HyPoradise / GER (arXiv:2309.15701)](https://arxiv.org/abs/2309.15701)
- [Qwen2-Audio (arXiv:2407.10759)](https://arxiv.org/abs/2407.10759)
- [Qwen2.5-Omni (arXiv:2503.20215)](https://arxiv.org/abs/2503.20215)
- [SALMONN (arXiv:2310.13289)](https://arxiv.org/abs/2310.13289)
- [WavLLM (arXiv:2404.00656)](https://arxiv.org/abs/2404.00656)

### 商业服务
- [Deepgram Models/Languages](https://developers.deepgram.com/docs/models-languages-overview)
- [Google Cloud Speech-to-Text V2](https://docs.cloud.google.com/speech-to-text/v2/docs)
- [Gemini API Audio](https://ai.google.dev/gemini-api/docs/audio)
- [Azure Speech](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/)
- [讯飞语音听写](https://www.xfyun.cn/services/voicedictation)
- [腾讯云 ASR](https://cloud.tencent.com/product/asr)
- [Amazon Transcribe](https://docs.aws.amazon.com/transcribe/latest/dg/supported-languages.html)
- [AssemblyAI Universal-2](https://www.assemblyai.com/blog/universal-2)
