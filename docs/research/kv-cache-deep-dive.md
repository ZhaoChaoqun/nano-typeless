# KV Cache 深入浅出：大语言模型推理的核心加速机制

*2026-03-09*

---

## 目录

1. [先修知识：Transformer 自注意力机制](#1-先修知识transformer-自注意力机制)
2. [核心问题：为什么需要 KV Cache？](#2-核心问题为什么需要-kv-cache)
3. [工作原理：KV Cache 如何运作](#3-工作原理kv-cache-如何运作)
4. [内存占用分析](#4-内存占用分析)
5. [优化技术全景](#5-优化技术全景)
6. [实际影响与选择指南](#6-实际影响与选择指南)

---

## 1. 先修知识：Transformer 自注意力机制

### 1.1 自注意力的核心计算

给定输入序列 $X \in \mathbb{R}^{n \times d}$（$n$ 为序列长度，$d$ 为隐藏维度），自注意力通过三个线性投影生成 Query、Key、Value：

$$Q = XW_Q, \quad K = XW_K, \quad V = XW_V$$

注意力输出为：

$$\text{Attention}(Q, K, V) = \text{softmax}\left(\frac{QK^T}{\sqrt{d_k}}\right) V$$

其中 $d_k$ 是每个注意力头的 Key 向量维度。分母中的 $\sqrt{d_k}$ 是**缩放因子**（scaling factor），这也是该机制被称为 **Scaled Dot-Product Attention** 的原因。

**为什么要缩放？** 假设 $Q$ 和 $K$ 的每个分量都是均值 0、方差 1 的独立随机变量，那么它们点积的方差为 $d_k$。当 $d_k$ 较大时（如 128），点积值的绝对值会很大（量级约 $\pm\sqrt{d_k} \approx \pm 11$），导致 softmax 输出接近 one-hot 分布，梯度趋近于 0（**梯度消失**）。除以 $\sqrt{d_k}$ 将点积的方差归一化回 1，使 softmax 保持平滑的梯度分布。

| | 点积值范围 | softmax 行为 |
|--|:---------:|:----------:|
| 不缩放（$d_k=128$） | 约 $\pm 11$ | 接近 one-hot，梯度消失 |
| 除以 $\sqrt{d_k}$ | 约 $\pm 1$ | 分布平滑，梯度正常 |

### 1.2 多头注意力（MHA）

实际中使用多头注意力，将 $d$ 维空间拆分为 $n_h$ 个头，每个头独立计算注意力后拼接：

$$\text{MultiHead}(Q, K, V) = \text{Concat}(\text{head}_1, ..., \text{head}_{n_h}) W_O$$

每个头的 K、V 维度为 $d_h = d / n_h$。

**直观类比：** 自注意力就像一个会议室里的人互相交流。每个人（token）需要看到所有人说了什么（K 和 V），才能形成自己的理解（attention output）。多头注意力相当于同时在多个不同主题的分组讨论中进行交流。

---

## 2. 核心问题：为什么需要 KV Cache？

### 2.1 自回归解码的重复计算灾难

LLM 生成文本是**自回归**（autoregressive）的：逐 token 生成，第 $t$ 个 token 依赖前面所有 $t-1$ 个 token。

**没有 KV Cache 时的计算过程：**

| 生成步骤 | 需计算 K/V 的 token 数 | 其中重复计算 |
|---------|---------------------|-----------|
| 第 1 步 | 1 | 0 |
| 第 2 步 | 2 | 1 个重复 |
| 第 3 步 | 3 | 2 个重复 |
| ... | ... | ... |
| 第 T 步 | T | T-1 个重复 |

生成 $T$ 个 token 时，K/V 的总投影计算量为：

$$\sum_{t=1}^{T} t = \frac{T(T+1)}{2} = O(T^2)$$

**直观类比：** 想象你在写一篇文章，每写一个新字，都要从第一个字开始重新读一遍全文。写 1000 字就要重读约 50 万次——这就是没有 KV Cache 的情况。

### 2.2 有了 KV Cache 之后

每一步只需为新生成的那 **1 个 token** 计算 K 和 V，之前 token 的结果直接从缓存读取：

$$T \times O(1) = O(T)$$

**从 $O(T^2)$ 降至 $O(T)$**——生成 1000 个 token 时，约节省 500 倍的 KV 投影计算量。

---

## 3. 工作原理：KV Cache 如何运作

### 3.1 两阶段推理流程

LLM 推理分为两个特征截然不同的阶段：

#### Prefill 阶段（首 token 延迟）

- 输入完整 prompt（例如 512 个 token）
- 一次性**并行**计算所有 token 的 Q、K、V
- 这是**矩阵-矩阵乘法**，可充分利用 GPU 并行能力（compute-bound）
- 将所有 K、V 存入缓存
- 输出第一个 token

#### Decode 阶段（逐 token 生成）

- 每步只处理 **1 个**新 token
- 为新 token 计算 $q_t$、$k_t$、$v_t$
- 将 $k_t$、$v_t$ **追加到缓存末尾**
- 用 $q_t$ 与缓存中所有 K 做点积，再与所有 V 做加权求和
- 这是**矩阵-向量乘法**，GPU 利用率低（memory-bound）

### 3.2 缓存的具体操作

以 Decode 阶段第 $t$ 步为例：

```
缓存状态（第 t-1 步结束时）：
  K_cache = [k_1, k_2, ..., k_{t-1}]   # shape: (t-1, n_layers, n_heads, d_head)
  V_cache = [v_1, v_2, ..., v_{t-1}]

第 t 步操作：
  1. 输入 token_t → embedding + 前几层 → 得到 h_t
  2. 计算: q_t = h_t·W_Q,  k_t = h_t·W_K,  v_t = h_t·W_V
  3. 追加: K_cache ← [K_cache; k_t],  V_cache ← [V_cache; v_t]
  4. 注意力: attn = softmax(q_t @ K_cache^T / √d_k) @ V_cache
  5. 输出 → 下一层 → ... → 最终得到 token_{t+1}
```

### 3.3 图解

```
                    没有 KV Cache                    有 KV Cache
                    ────────────                    ──────────

生成 token 4:       [t1 t2 t3] → 全部重算 K,V       [t3] → 只算 k3,v3
                    Q(3×d) × K(3×d)^T               追加到 cache
                                                     q3 × K_cache(3×d)^T

生成 token 5:       [t1 t2 t3 t4] → 全部重算 K,V    [t4] → 只算 k4,v4
                    Q(4×d) × K(4×d)^T               追加到 cache
                                                     q4 × K_cache(4×d)^T
```

---

## 4. 内存占用分析

### 4.1 显存消耗公式

**单个 token 的 KV Cache 大小：**

$$\text{mem}_{\text{token}} = 2 \times n_{\text{layers}} \times n_{\text{kv\_heads}} \times d_{\text{head}} \times \text{sizeof(dtype)}$$

- $2$ = Key 和 Value 两份
- $n_{\text{layers}}$ = Transformer 层数
- $n_{\text{kv\_heads}}$ = KV 头数（标准 MHA 中等于 $n_h$）
- $d_{\text{head}}$ = 每头维度
- sizeof(dtype) = FP16 为 2 bytes，FP32 为 4 bytes

**总 KV Cache 大小：**

$$\text{Total} = \text{batch\_size} \times \text{seq\_len} \times \text{mem}_{\text{token}}$$

### 4.2 具体模型计算实例

**LLaMA-2 7B（FP16）：**

- $n_{\text{layers}} = 32$, $n_{\text{heads}} = 32$, $d_{\text{head}} = 128$
- 单 token = $2 \times 32 \times 32 \times 128 \times 2 = 524\text{KB} \approx 0.5\text{MB}$
- 4096 tokens 上下文 ≈ **2 GB**
- 10000 tokens 上下文 ≈ **5 GB**（约为模型参数量 14GB 的 1/3）

**不同模型对比：**

| 模型 | 参数显存 (FP16) | KV Cache (4K ctx, bs=1) | 占比 |
|------|:-----------:|:-------------------:|:---:|
| LLaMA-2 7B | ~14 GB | ~2 GB | ~14% |
| LLaMA-2 13B | ~26 GB | ~3.2 GB | ~12% |
| LLaMA-2 70B (GQA) | ~140 GB | ~2.5 GB | ~1.8% |

> LLaMA-2 70B 使用了 GQA（8 个 KV 头 vs 64 个 Query 头），所以 KV Cache 反而比预期小很多。

### 4.3 KV Cache 是部署的最大瓶颈之一

KV Cache 随 batch_size 和 seq_len **线性增长**：

- 增大 batch size 提高吞吐 → KV Cache 爆炸 → 显存不足
- 增大上下文窗口 → KV Cache 爆炸 → 显存不足

**A100 80GB 上（LLaMA-2 7B）：**

| 配置 | 可支持最大 token 数 |
|------|:----------------:|
| FP16 KV Cache | ~40K tokens |
| INT4 量化 KV Cache | ~128K tokens |

---

## 5. 优化技术全景

### 5.1 架构层面：减少 KV 头数

#### Multi-Query Attention (MQA)

> Shazeer, "Fast Transformer Decoding: One Write-Head is All You Need" (2019)

所有 Query 头共享**同一组** K 和 V：

```
MHA:  32 个 Q 头, 32 个 K 头, 32 个 V 头  →  KV Cache = 2 × 32 × d_h
MQA:  32 个 Q 头,  1 个 K 头,  1 个 V 头  →  KV Cache = 2 ×  1 × d_h
                                              ↑ 缩减 32 倍
```

代表模型：PaLM, StarCoder, Falcon

#### Grouped-Query Attention (GQA)

> Ainslie et al., "GQA: Training Generalized Multi-Query Transformer Models" (EMNLP 2023)

MHA 和 MQA 之间的折中——将 Query 头分成 $g$ 组，每组共享一套 K/V：

```
MHA:   32 Q 头, 32 KV 头   (每头独立)
GQA:   32 Q 头,  8 KV 头   (每 4 个 Q 头共享 1 组 KV)
MQA:   32 Q 头,  1 KV 头   (所有头共享)
```

| 方法 | KV 头数 | 质量 | 推理速度 |
|------|:------:|:----:|:------:|
| MHA | $n_h$ | 最高 | 最慢 |
| **GQA** | $n_{kv}$ | **接近 MHA** | **接近 MQA** |
| MQA | 1 | 可能下降 | 最快 |

代表模型：LLaMA-2 70B, Mistral, Gemma

#### Multi-head Latent Attention (MLA)

> DeepSeek-AI, "DeepSeek-V2" (2024)

用**低秩联合压缩**将 K 和 V 压缩到一个低维潜在向量 $c_t$：

$$c_t = W_{DKV} \cdot h_t, \quad d_c \ll n_h \times d_h$$

推理时通过**矩阵吸收**技巧，注意力直接在 $c_t$ 上计算，无需恢复完整 K/V。

| 方法 | 每 token 缓存量 | 相对 MHA |
|------|:------------:|:-------:|
| MHA | $2 \times n_h \times d_h$ | 100% |
| GQA (8 heads) | $2 \times 8 \times d_h$ | ~12.5% |
| MQA | $2 \times d_h$ | ~3.1% |
| **MLA** | $d_c$ | **~6.7%** |

**直观类比：** MHA 是为每场会议录完整视频，GQA 是几组共用摄像机，MQA 是全场只有一台摄像机，MLA 是把所有视频压缩成一段精华摘要——需要时再还原。

### 5.2 系统层面：PagedAttention

> Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention" (SOSP 2023) — vLLM

**核心问题：** 传统 KV Cache 按最大长度预分配连续内存，导致 **60-80% 显存浪费**。

**解决方案：** 借鉴操作系统**虚拟内存分页**：

| OS 概念 | PagedAttention |
|---------|:-------------:|
| 页 (Page) | 块 (Block) |
| 进程 (Process) | 序列 (Sequence) |
| 页表 | 块表 (Block Table) |

- 将 KV Cache 分割为固定大小的块
- 通过块表映射到**非连续**物理块
- 按需分配，支持 Copy-on-Write

**实测效果：**

| 对比 | 提升 |
|------|:---:|
| vLLM vs HuggingFace Transformers | 最高 **24x** 吞吐 |
| vLLM vs HuggingFace TGI | 最高 **3.5x** 吞吐 |
| 内存浪费率 | 从 60-80% 降至 **< 4%** |

### 5.3 KV Cache 量化

将 K/V 从 FP16 量化为 INT8/INT4：

| 量化位数 | 空间节省 | 质量影响 |
|:-------:|:-------:|:------:|
| INT8 | ~2x | 几乎无损 |
| INT4 | ~4x | 困惑度接近 FP16 |
| INT2 | ~8x | 质量明显下降 |

### 5.4 窗口与淘汰策略

#### StreamingLLM

> Xiao et al., "Efficient Streaming Language Models with Attention Sinks" (ICLR 2024)

发现 **Attention Sink** 现象：LLM 对序列开头几个 token 赋予极高注意力权重，无论其语义是否重要。

解决方案：保留少量"汇聚 token"KV + 滑动窗口最近 token KV，淘汰中间部分。

- 支持**无限长度**生成（已验证 400 万+ tokens）
- 比滑动窗口重计算快 **22.2x**

---

## 6. 实际影响与选择指南

### 6.1 KV Cache 的速度提升

| | 无 KV Cache | 有 KV Cache |
|--|:-----------:|:----------:|
| KV 投影计算复杂度 | $O(T^2)$ | $O(T)$ |
| 生成 1000 token 的 KV 投影量 | ~500K 次 | ~1K 次 |

### 6.2 技术选择指南

| 场景 | 推荐方案 |
|------|---------|
| 训练新模型，极致效率 | **MLA** (DeepSeek 系列) |
| 训练新模型，质量/效率平衡 | **GQA** (LLaMA-2, Mistral) |
| 已有 MHA 模型 | GQA uptrain（仅需 5% 预训练计算量） |
| 部署服务端推理 | **PagedAttention** (vLLM) |
| 超长上下文 | KV Cache **INT4 量化** + FlashAttention |
| 流式无限长度生成 | **StreamingLLM** |

---

## 一句话总结

KV Cache 用空间换时间，将自回归解码从 $O(T^2)$ 降至 $O(T)$；但它带来的显存压力成为 LLM 部署的核心瓶颈，催生了从模型架构（MQA → GQA → MLA）到系统工程（PagedAttention）到数值精度（量化）的一整套优化技术栈。

---

## 参考文献

- Shazeer, "Fast Transformer Decoding: One Write-Head is All You Need" (2019) — MQA
- Ainslie et al., "GQA: Training Generalized Multi-Query Transformer Models" (EMNLP 2023) — GQA
- DeepSeek-AI, "DeepSeek-V2" (2024) — MLA
- Kwon et al., "Efficient Memory Management for LLM Serving with PagedAttention" (SOSP 2023) — vLLM
- Xiao et al., "Efficient Streaming Language Models with Attention Sinks" (ICLR 2024) — StreamingLLM
