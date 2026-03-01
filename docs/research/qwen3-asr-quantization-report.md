# Qwen3-ASR 模型量化版本调研报告

> 日期：2026-02-27

## 1. 背景

当前项目使用的是 Qwen3-ASR-0.6B 原始精度模型，存放于本地，总大小约 **1.8 GB**。为探索更小体积、更快推理速度的部署方案，对 ModelScope 及 Hugging Face 上的量化版本和社区转换资源进行了调研。

---

## 2. 本地模型 vs ModelScope 量化版本对比

### 2.1 本地文件（Qwen3-ASR-0.6B 原始精度）

| 文件 | 大小 |
|------|------|
| `model.safetensors` | 1.7 GB |
| `config.json` | 6.0 KB |
| `generation_config.json` | 142 B |
| `merges.txt` | 1.6 MB |
| `preprocessor_config.json` | 330 B |
| `tokenizer_config.json` | 12 KB |
| `vocab.json` | 2.6 MB |
| **总计** | **~1.8 GB** |

### 2.2 ModelScope 量化版本（Qwen3-ASR-0.6B-w4a16）

| 文件 | 大小 |
|------|------|
| `model.safetensors` | ~612 MB |
| **总计** | **~627 MB** |

- 来源：[baicai1145/Qwen3-ASR-0.6B-w4a16](https://www.modelscope.cn/models/baicai1145/Qwen3-ASR-0.6B-w4a16/files)
- 量化方案：**w4a16**（权重 4-bit，激活值 16-bit）
- 体积缩小约 **65%**，会有轻微精度损失

### 2.3 大小差异原因

模型参数量约 4.81 亿个：

- **FP32 存储**：4.81×10⁸ × 4 bytes ≈ 1.8 GB（与本地大小吻合）
- **4-bit 量化**：4.81×10⁸ × 0.5 bytes ≈ 0.24 GB（加上部分参数保持 FP16/FP32 + 量化元数据 ≈ 612 MB）

---

## 3. 官方量化版本情况

Qwen 官方（阿里云）**未发布** w8 或 w16 的量化版本，仅提供原始精度模型：

- `Qwen3-ASR-0.6B`
- `Qwen3-ASR-1.7B`

ModelScope 上的 `baicai1145/Qwen3-ASR-0.6B-w4a16` 为**社区用户**提供的量化版本，非官方出品。

---

## 4. 模型格式对比

| 格式 | 全称 | 出品方 | 量化方式 | 运行平台 | 推理框架 | 典型使用场景 | 优势 | 局限 |
|------|------|--------|----------|----------|----------|-------------|------|------|
| **SafeTensors** | Safe Tensors | Hugging Face | 无（原始精度 FP32/FP16/BF16） | 全平台 | PyTorch、Transformers | 训练、微调、精度敏感的推理 | 安全性高（防代码注入）、加载速度快、HF 生态标配 | 体积大，无内置量化能力 |
| **GGUF** | GPT-Generated Unified Format | ggml-org（Georgi Gerganov） | 支持多种（Q2_K ~ Q8_0、F16 等） | 全平台（CPU 友好） | llama.cpp、Ollama、LM Studio | 本地 CPU/GPU 混合推理、桌面端部署 | 单文件包含全部信息、量化粒度灵活、跨平台、CPU 推理性能优秀 | 非训练格式，需从原始模型转换 |
| **MLX** | Apple MLX Format | Apple | 支持 4/5/6/8-bit、BF16 | macOS / Apple Silicon 专用 | MLX 框架 | Mac 上的本地推理 | Apple 统一内存架构下性能最优、转换工具成熟 | 仅限 Apple 平台，生态较封闭 |
| **ONNX** | Open Neural Network Exchange | Microsoft（现由 Linux 基金会托管） | 支持 INT8、FP16 等 | 全平台（含移动端、嵌入式） | ONNX Runtime、sherpa-onnx | 跨平台部署、移动端、边缘设备、浏览器 (WASM) | 跨平台标准格式、运行时优化成熟、支持硬件加速器 | 模型转换可能丢失自定义算子，调试较困难 |
| **CoreML** | Core ML | Apple | 支持 FP16、INT8 等 | iOS / macOS 专用 | Apple Core ML | iOS/macOS App 内嵌推理 | 深度集成 Apple 生态（ANE/GPU/CPU 自动调度）、功耗低 | 仅限 Apple 平台，模型转换兼容性有限 |
| **GPTQ** | GPT Quantization | IST-DASLab（Elias Frantar 等） | 权重 INT4/INT8（逐层校准量化） | 需要 NVIDIA GPU | AutoGPTQ、Transformers | GPU 上大模型推理、显存受限场景 | 量化精度高（有校准数据）、GPU 推理速度快 | 需要 GPU，量化过程耗时，CPU 推理不友好 |
| **AWQ** | Activation-aware Weight Quantization | MIT（Ji Lin、韩松团队） | 权重 INT4（基于激活感知） | 需要 NVIDIA GPU | AutoAWQ、vLLM、TGI | GPU 推理、服务端大规模部署 | 比 GPTQ 更快的推理速度、更好的精度保持 | 需要 GPU，格式支持的框架较少 |
| **OpenVINO** | Open Visual Inference & Neural Network Optimization | Intel | 支持 INT8、FP16 | Intel CPU/GPU/VPU | OpenVINO Runtime | Intel 平台推理优化、边缘部署 | 针对 Intel 硬件深度优化、支持异构计算 | 仅 Intel 平台性能优势显著，其他平台无优势 |

### 格式选择建议

```
                       ┌─ 训练/微调 ─────────────── SafeTensors (原始精度)
                       │
                       ├─ Mac 本地推理 ──────────── MLX (Apple Silicon 最优)
                       │                            CoreML (iOS/macOS App 集成)
                       │
你的模型用途是？ ──────┼─ 桌面/服务器 CPU 推理 ──── GGUF (llama.cpp 生态)
                       │
                       ├─ GPU 推理 (NVIDIA) ─────── AWQ > GPTQ (速度与精度平衡)
                       │
                       ├─ 跨平台/移动端/嵌入式 ──── ONNX (最广泛兼容)
                       │
                       └─ Intel 平台专用 ────────── OpenVINO
```

### 附：FP16 与 BF16 的区别

FP16 和 BF16 都是 16-bit 浮点数格式，占用相同的存储空间（每个参数 2 bytes），但位分配方式不同，导致精度和表示范围存在显著差异。

#### 位结构对比

```
FP32:  1 位符号 + 8 位指数 + 23 位尾数  （共 32 位）
FP16:  1 位符号 + 5 位指数 + 10 位尾数  （共 16 位）
BF16:  1 位符号 + 8 位指数 +  7 位尾数  （共 16 位）
```

#### 核心差异

| 维度 | FP32 | FP16 | BF16 |
|------|------|------|------|
| **全称** | Float 32 | Float 16 / Half Precision | Brain Floating Point 16 |
| **出品方** | IEEE 标准 | IEEE 标准 | Google Brain |
| **存储大小** | 4 bytes | 2 bytes | 2 bytes |
| **指数位数** | 8 位 | 5 位 | 8 位 |
| **尾数位数** | 23 位 | 10 位 | 7 位 |
| **数值范围** | ±3.4×10³⁸ | ±6.5×10⁴ | ±3.4×10³⁸ |
| **精度（有效数字）** | ~7 位十进制 | ~3.3 位十进制 | ~2.4 位十进制 |
| **溢出风险** | 极低 | **高**（范围小，训练中容易溢出） | 低（范围与 FP32 相同） |
| **精度损失** | 基准 | 中等 | 较高（尾数短） |
| **硬件支持** | 全部 | NVIDIA GPU、Apple ANE | NVIDIA Ampere+、Google TPU、Apple M 系列 |

#### 选择建议

| 场景 | 推荐格式 | 原因 |
|------|----------|------|
| **模型训练** | BF16 | 数值范围大，不易溢出，梯度更新更稳定 |
| **推理部署（GPU）** | FP16 | 精度更高，推理无梯度溢出问题，硬件支持更广 |
| **推理部署（Apple Silicon）** | BF16 | M 系列芯片原生支持，MLX 生态默认格式 |
| **从 FP32 模型转换** | BF16 | 直接截断尾数即可，不需要缩放处理，转换简单无损范围 |

> **简单理解**：BF16 牺牲精度换取了与 FP32 相同的数值范围（"粗糙但不溢出"）；FP16 牺牲范围换取了更高的精度（"精确但容易溢出"）。对于大模型而言，BF16 在训练阶段更安全，FP16 在推理阶段更常见。

### 附：Apple MLX 与 CoreML 的区别

MLX 和 CoreML 都是 Apple 的机器学习框架，但定位、设计目标和使用方式有本质不同。

| 维度 | MLX | CoreML |
|------|-----|--------|
| **全称** | Machine Learning eXploration | Core Machine Learning |
| **开发团队** | Apple 机器学习研究团队 | Apple 系统框架团队 |
| **开源** | 是（Apache 2.0，GitHub 开源） | 否（闭源，仅提供 SDK） |
| **首次发布** | 2023 年 12 月 | 2017 年（WWDC 2017） |
| **定位** | 研究与实验框架，面向 ML 开发者/研究者 | 应用部署框架，面向 App 开发者 |
| **类比** | 类似 Apple 版的 PyTorch | 类似 Apple 版的 TensorFlow Lite |
| **支持训练** | 是（支持训练 + 微调 + 推理） | 否（仅推理，不支持训练） |
| **编程语言** | Python / Swift / C++ | Swift / Objective-C |
| **运行平台** | macOS（Apple Silicon） | macOS + iOS + iPadOS + watchOS + tvOS |
| **硬件调度** | GPU + CPU（统一内存，惰性计算） | ANE + GPU + CPU（自动调度） |
| **ANE 支持** | 不直接支持 Apple Neural Engine | 核心优势，深度利用 ANE 加速 |
| **内存模型** | 统一内存，CPU/GPU 零拷贝共享 | 框架自动管理，对开发者透明 |
| **模型格式** | `.npz` / `.safetensors`（MLX 权重） | `.mlmodel` / `.mlpackage` |
| **生态工具** | mlx-lm、mlx-audio、mlx-vlm | coremltools（模型转换工具） |
| **典型用途** | 本地跑 LLM、语音模型研究与实验 | App 内嵌 AI 功能（视觉、语音、NLP） |
| **功耗优化** | 一般（研究优先） | 优秀（ANE 功耗极低，适合移动端） |
| **模型来源** | HF 模型直接加载或社区转换 | 需通过 coremltools 从 PyTorch/TF 转换 |

#### 关键区别总结

| 维度 | MLX | CoreML |
|------|-----|--------|
| **面向对象** | ML 研究者 | App 开发者 |
| **核心能力** | 训练 + 微调 + 推理 | 仅推理（部署） |
| **硬件利用** | GPU + CPU（统一内存） | ANE + GPU + CPU（自动调度） |
| **运行平台** | 仅 macOS | 全 Apple 平台 |
| **典型场景** | "在 Mac 上跑 LLM"、"本地微调模型" | "在 iPhone App 中集成语音识别" |

#### 选择建议

| 场景 | 推荐框架 | 原因 |
|------|----------|------|
| Mac 上本地运行/实验 LLM 或语音模型 | **MLX** | 支持训练微调、HF 生态直接对接、统一内存利用率高 |
| iOS/macOS App 产品化部署 | **CoreML** | 全平台支持、ANE 硬件加速、功耗低、与 Xcode 深度集成 |
| 需要在移动端实时语音识别 | **CoreML** | ANE 加速推理速度快且省电，适合长时间运行 |
| 模型研究、快速原型验证 | **MLX** | Python API 友好、开源可调试、社区模型丰富 |
| macOS App 集成且追求极致性能 | **CoreML** | ANE 加速是 MLX 目前不具备的优势 |

---

## 5. 社区量化版本汇总

### 4.1 MLX 格式（Apple Silicon 专用）

| 模型 | 量化精度 | 大小 | 来源 |
|------|----------|------|------|
| `mlx-community/Qwen3-ASR-0.6B-bf16` | BF16 (16-bit) | ~0.8B | Hugging Face |
| `mlx-community/Qwen3-ASR-0.6B-8bit` | 8-bit | ~0.4B | Hugging Face |
| `mlx-community/Qwen3-ASR-0.6B-6bit` | 6-bit | ~0.3B | Hugging Face |
| `mlx-community/Qwen3-ASR-0.6B-5bit` | 5-bit | ~0.3B | Hugging Face |
| `mlx-community/Qwen3-ASR-0.6B-4bit` | 4-bit | ~0.3B | Hugging Face |

### 4.2 其他格式

| 模型 | 格式 | 说明 |
|------|------|------|
| `dseditor/Qwen3-ASR-1.7B-INT8_OpenVINO` | OpenVINO INT8 | Intel 平台推理 |
| `FluidInference/qwen3-asr-0.6b-coreml` | CoreML | Apple 设备原生推理 |
| `OpenVoiceOS/qwen3-asr-0.6b-q4-k-m` | GGUF Q4_K_M | llama.cpp 兼容 |
| `FlippyDora/qwen3-asr-1.7b-GGUF` | GGUF | llama.cpp 兼容 |
| `ReopenAI/Qwen3-omni-ASR-GPTQ-Int4` | GPTQ Int4 | GPU 推理 |
| `Luigi/Qwen3-ASR-0.6B-chatllm-quantized` | ChatLLM | 专用格式 |

---

## 5. 主要模型转换社区对比

### 5.1 总览

| 社区/个人 | 关注者 | 模型数 | 主要格式 | 侧重领域 | 活跃状态 |
|-----------|--------|--------|----------|----------|----------|
| **TheBloke** | 26,619 | 3,863 | GGUF/GPTQ/AWQ | LLM 量化（通用） | 已停更（2024.1 后） |
| **bartowski** | 10,020 | 2,270 | GGUF | LLM 量化（通用） | 活跃 |
| **mlx-community** | 8,978 | 4,072 | MLX | Apple Silicon 专用 | 活跃 |
| **ggml-org** | 1,399 | 147 | GGUF | llama.cpp 官方转换 | 活跃 |
| **k2-fsa (sherpa)** | 较小 | 23 | ONNX/sherpa | 语音识别专用 | 活跃 |

### 5.2 详细分析

| 维度 | mlx-community | k2-fsa / sherpa-onnx | TheBloke | bartowski | ggml-org |
|------|---------------|----------------------|----------|-----------|----------|
| **背景** | Apple MLX 团队 + Hugging Face 员工共同推动 | Daniel Povey（Kaldi 创始人）领导的 "Next-gen Kaldi" 项目 | 个人开发者 Tom Jobbins，曾是开源 LLM 量化代名词 | Arcee AI 研究工程师，当前最活跃的 GGUF 量化者 | ggml/llama.cpp 创始人 Georgi Gerganov 的官方组织 |
| **核心成员** | HF 员工（Pedro Cuenca、Omar Sanseviero）、MLX 开发者（Awni Hannun） | 17 名成员，语音识别领域顶级学者 | 个人 | 个人（Arcee AI 背景） | Georgi Gerganov 等 11 名核心开发者 |
| **规模** | 3,818 成员、4,072 模型、122 Collections | 23 模型、36 Spaces | 26,619 关注者、3,863 模型 | 10,020 关注者、2,270 模型 | 1,399 关注者、147 模型 |
| **主要格式** | MLX | ONNX | GGUF / GPTQ / AWQ | GGUF | GGUF |
| **优势** | Apple Silicon 最大模型库，一键转换工具完善 | 语音领域权威，跨平台部署（移动端、浏览器、嵌入式） | 覆盖面极广，几乎所有主流 LLM 都有量化版 | 更新快、覆盖新模型及时，提供量化质量分析 | GGUF 格式的定义者，转换质量最有保障 |
| **局限** | 仅限 Apple 平台，格式不通用 | 专注语音领域，模型数量少，社区规模小 | 2024 年 1 月后停止更新 | 主要只做 GGUF 格式 | 模型数量少，只转换部分代表性模型 |
| **可信度** | **高** — Apple + HF 官方背书 | **非常高** — Povey 是语音识别领域最有影响力人物 | **高** — 但不再维护 | **高** — 专业背景 + 社区认可，TheBloke 继任者 | **最高** — GGUF 格式标准制定者 |
| **活跃状态** | 活跃 | 活跃 | 已停更 | 活跃 | 活跃 |

---

## 6. 针对项目的建议方案

| 方案 | 社区 | 格式 | 体积 | 适用场景 |
|------|------|------|------|----------|
| `mlx-community/Qwen3-ASR-0.6B-8bit` | mlx-community | MLX | ~0.4 GB | Mac 原生推理，性能与精度平衡 |
| `mlx-community/Qwen3-ASR-0.6B-bf16` | mlx-community | MLX | ~0.8 GB | Mac 原生推理，接近原始精度 |
| sherpa-onnx 转换模型 | k2-fsa | ONNX | 视转换精度 | 跨平台部署、移动端、嵌入式 |
| 当前本地原始模型 | Qwen 官方 | safetensors | ~1.8 GB | 精度最高，体积最大 |

**结论**：

- **mlx-community** 和 **k2-fsa/sherpa** 都是可信赖的社区，但定位不同
- 若仅在 Mac 上使用，**mlx-community** 的版本更合适（Apple Silicon 原生优化）
- 若需部署到移动端或嵌入式设备，**sherpa-onnx** 更专业
- 若追求最高精度且不在意体积，保持当前原始模型即可
