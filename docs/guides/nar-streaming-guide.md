# NAR 模型怎么做 Streaming？— Paraformer 流式方案详解

## 核心矛盾

非自回归（NAR）模型的核心优势是**一次性并行输出所有 token**，比自回归快 10 倍以上。但这有一个前提——**需要看到完整的音频**才能工作：

```
离线 NAR:
  [======= 完整音频 (10s) =======] -> Encoder -> CIF -> Decoder -> "今天天气真不错"
                                                                    (一次出全部)
```

这和"边说边出字"的 streaming 需求直接矛盾。用户不可能说完 10 秒话再看到第一个字。

**Paraformer 的解决思路：既然不能等完整音频，那就把音频切成小块（chunk），每块内部仍然是 NAR 并行解码。**

---

## 离线 Paraformer 的三个核心组件

在理解流式改造之前，先回顾离线版 Paraformer 的架构：

```
audio -> [Encoder] -> [CIF Predictor] -> [Decoder] -> text
            |              |                 |
         Conformer      预测token数量      并行解码
         双向注意力      生成隐藏变量       GLM增强
```

### 1. Encoder（编码器）

- 使用 Conformer 架构（Transformer + 卷积）
- **双向注意力**：每一帧都能看到整段音频的过去和未来
- 输出：每帧音频对应一个特征向量（帧级表示）

### 2. CIF Predictor（连续积分触发器）— 最关键的创新

CIF 是 Paraformer 的核心，解决了 NAR 模型最大的难题：**怎么知道该输出几个 token？**

#### 为什么这是个难题？

AR 模型不需要提前知道输出多少 token——它一个接一个生成，直到输出 `[EOS]`（结束符）就停了。但 NAR 模型要**一次性并行生成所有 token**，所以必须提前知道"这段音频对应几个字"。

问题是，同样长度的音频可能对应截然不同数量的文字：

```
2 秒音频: "好" (1个字) -- 说话很慢、带停顿
2 秒音频: "今天天气真不错" (7个字) -- 正常语速
2 秒音频: "我觉得这个方案应该可以试一试" (13个字) -- 说话很快
```

CIF 的作用就是**从音频特征中自动推断出该输出几个 token，并为每个 token 生成对应的声学表示**。

#### 日常类比：水龙头接水

把 CIF 想象成用杯子在水龙头下接水：

```
水龙头(Encoder输出):  每帧滴出不同量的水(权重)
杯子(容量=1.0):      接满一杯就拿走，换新杯子

  滴  滴  滴滴滴  滴  滴滴  滴滴滴滴  滴
  |   |   |       |   |     |          |
  0.3 0.4 0.6     0.2 0.5   0.7        0.8
  [       ]       [       ] [             ]
  杯子1:满了!      杯子2:满了! 杯子3:满了!
  拿走=token1     拿走=token2 拿走=token3
```

每"拿走一杯"就是产生一个 token。水流大（权重高）的帧说明那里的语音信息密集（比如有辅音爆破），水流小的帧说明信息稀疏（比如元音持续段）。

#### 详细计算过程

```
Encoder 输出 8 帧，每帧附带一个权重值(由一个小型线性层预测)：

帧:    f1     f2     f3     f4     f5     f6     f7     f8
权重:  0.3    0.4    0.6    0.2    0.5    0.7    0.1    0.8

逐帧累加：

f1: 累计 = 0.0 + 0.3 = 0.3  (< 1.0, 不触发)
f2: 累计 = 0.3 + 0.4 = 0.7  (< 1.0, 不触发)
f3: 累计 = 0.7 + 0.6 = 1.3  (>= 1.0, 触发!)
    token 1 的表示 = f1 * 0.3 + f2 * 0.4 + f3 * 0.3
                                                 ^-- 只取 0.3 凑满 1.0
    累计重置: 1.3 - 1.0 = 0.3 (余额, 属于 f3 的剩余部分)

f4: 累计 = 0.3 + 0.2 = 0.5  (< 1.0, 不触发)
f5: 累计 = 0.5 + 0.5 = 1.0  (>= 1.0, 触发!)
    token 2 的表示 = f3 * 0.3 + f4 * 0.2 + f5 * 0.5
                      ^-- f3 的余额
    累计重置: 1.0 - 1.0 = 0.0

f6: 累计 = 0.0 + 0.7 = 0.7  (< 1.0, 不触发)
f7: 累计 = 0.7 + 0.1 = 0.8  (< 1.0, 不触发)
f8: 累计 = 0.8 + 0.8 = 1.6  (>= 1.0, 触发!)
    token 3 的表示 = f6 * 0.7 + f7 * 0.1 + f8 * 0.2
                                                 ^-- 只取 0.2 凑满 1.0
    累计重置: 1.6 - 1.0 = 0.6 (余额)
```

#### CIF 输出什么？

两样东西：

| 输出 | 内容 | 作用 |
|------|------|------|
| token 数量 | 3（触发了 3 次） | 告诉 Decoder 要并行生成 3 个 token |
| 隐藏变量 | [h1, h2, h3]（每个是加权特征向量） | 作为 Decoder 的输入，携带声学信息 |

每个隐藏变量 h 是对应音频帧的**加权组合**，所以它天然包含了"这个 token 对应哪段音频"的位置信息——不需要像 AR 模型那样用位置编码。

#### 权重怎么来的？

权重由一个小型网络（通常是 1-2 层全连接 + sigmoid）从 Encoder 输出中预测：

```
Encoder 帧 fi (维度 512) -> Linear(512, 1) -> sigmoid -> 权重 wi (0~1)
```

这个小网络和整个 Paraformer 一起端到端训练。训练目标是让所有帧的权重之和等于目标文本的 token 数量：

```
训练损失 (CIF 部分):
  L_quantity = |sum(所有权重) - 目标token数|

例如:
  目标文本 "今天天气真不错" = 7 个 token
  所有帧权重之和应该接近 7.0
```

#### CIF vs 其他长度预测方法

| 方法 | 工作方式 | 优缺点 |
|------|---------|--------|
| **CTC length** | 用 CTC 对齐计算非空白 token 数 | 简单但粗糙，不生成隐藏变量 |
| **单独预测器** | 用 MLP 直接预测一个整数 | 不够精确，且无法生成每个 token 的表示 |
| **CIF（Paraformer）** | 逐帧累加权重，阈值触发 | 同时完成长度预测和隐藏变量生成，信息最丰富 |

CIF 的精妙之处在于：它不仅回答了"多少个 token"，还回答了"每个 token 对应哪些帧"——这种**软对齐**是 Paraformer 精度接近 AR 模型的关键原因。

---

### 3. GLM Sampler（扫视语言模型采样器）— NAR 质量的秘密武器

#### NAR 解码的天然缺陷

NAR 模型的 Decoder 一次性并行生成所有 token，意味着**每个 token 的预测互相独立**——token 1 不知道 token 2 会生成什么。

这就像让一个班的学生同时参加考试，但**不准看其他人的答案**：

```
AR 解码（允许作弊）:
  "今" -> 看到"今", 预测"天" -> 看到"今天", 预测"天" -> ...
  每一步都参考前面的答案，所以连贯

NAR 解码（不准作弊）:
  位置1: 根据声学特征猜 -> "今"
  位置2: 根据声学特征猜 -> "天"    这些预测互相独立!
  位置3: 根据声学特征猜 -> "天"    不知道其他位置猜了什么
  ...
```

独立预测的问题：如果位置 3 不知道位置 1 和 2 已经预测了"今天"，它可能会犯错——比如重复或漏字。

#### GLM 的解法：训练时教模型"看一点，猜剩余"

GLM = Glancing Language Model，字面意思是"扫一眼的语言模型"。

训练过程分两步：

**第一步：正常 NAR 解码，得到初始预测**

```
CIF 输出: [h1, h2, h3, h4, h5, h6, h7]
Decoder 並行预测: [今, 天, 天, 气, 真, 不, 错]
正确答案:         [今, 天, 天, 气, 真, 不, 错]

对比: 哪些位置预测对了? 哪些错了?
假设位置 5 和 7 预测错了 -> 错了 2 个
```

**第二步：采样 + 重新预测**

根据错误比例，随机采样一部分**正确答案**作为"提示"，让模型重新预测剩余部分：

```
采样比例 = 1 - 错误比例 = 1 - 2/7 ≈ 0.7

随机选择 70% 的位置揭示正确答案（遮盖 30%）:
位置:    1     2     3     4     5     6     7
揭示: [今]  [天]  [?]   [气]  [?]   [不]  [?]
                   ^^^         ^^^         ^^^
                   被遮盖       被遮盖      被遮盖

模型任务: 根据已揭示的 "今, 天, ?, 气, ?, 不, ?"
         推断被遮盖位置应该是什么
         -> 类似于完形填空!
```

#### 为什么这能提升质量？

通过这种训练方式，模型学会了：

```
学到的能力:
  - 如果位置 1,2 是 "今天"，位置 3 大概率是 "天"（因为"天气"是常见搭配）
  - 如果位置 4 是 "气"，位置 5 大概率是 "真/很/挺"（搭配概率）
  - 如果位置 6 是 "不"，位置 7 大概率是 "错/好/行"
```

训练时模型反复练习"从部分已知信息中推断未知"，推理时虽然没有"揭示"（所有位置同时预测），但模型内部的注意力机制已经学会了**在 token 之间建立依赖关系**。

#### 类比：完形填空训练法

| 训练方法 | 类比 | 效果 |
|---------|------|------|
| **普通 NAR** | 考试时完全不能看别人答案 | 每个答案独立，容易出错 |
| **GLM 增强 NAR** | 平时训练时做大量完形填空 | 考试时虽然独立答题，但已经学会了根据上下文推断 |
| **AR** | 考试时能看前面所有人的答案 | 最准确，但必须排队一个一个答 |

GLM 让 NAR 的精度**逼近** AR，同时保留了并行解码的速度优势。

#### 训练与推理的区别

```
训练时 (有 GLM 采样):
  输入: CIF隐藏变量 + 部分正确答案(采样)
  任务: 预测被遮盖的位置
  目的: 强迫模型学习 token 间依赖

推理时 (无 GLM 采样):
  输入: CIF隐藏变量 (无任何正确答案)
  任务: 一次性并行预测所有位置
  效果: 模型已从训练中学会上下文推断能力，自动应用
```

> **关键点：GLM 只在训练阶段起作用。** 推理时和普通 NAR 完全一样——一步并行出结果。
> GLM 的价值在于让模型在训练过程中学会了更好的内部表示。

---

### Encoder、CIF、GLM 协同工作的完整流程

```
                            Paraformer 完整推理流程
                            =======================

Step 1: Encoder
   原始音频 (16kHz PCM)
     |
     v
   Mel 频谱图 (80维 x T帧)
     |
     v
   Conformer Encoder (12层, 双向注意力+卷积)
     |
     v
   帧级特征: [f1, f2, f3, ..., fT]  (每帧 512 维向量)


Step 2: CIF Predictor
   帧级特征 [f1..fT]
     |
     v
   小型线性层: 每帧 -> 权重 wi (0~1)
     |
     v
   逐帧累加，阈值触发:
     权重之和 ≈ N (目标 token 数)
     每次触发生成一个隐藏变量 hi (加权特征组合)
     |
     v
   输出: [h1, h2, ..., hN]  (N 个 token 的隐藏变量)


Step 3: GLM 增强的 Decoder
   CIF 隐藏变量 [h1..hN]
     |
     v
   Transformer Decoder (6层, self-attention + cross-attention)
     - self-attention: token 间互相交流 (这是 GLM 训练的成果)
     - cross-attention: 每个 token 关注 Encoder 输出
     |
     v
   并行输出: [token_1, token_2, ..., token_N]
     |
     v
   文本: "今天天气真不错"
```

---

## 流式改造：三个组件分别怎么改

### 改造思路总览

```
离线版:
  [====== 完整音频 ======] -> Encoder(全局) -> CIF(全局) -> Decoder -> 全部文字

流式版:
  [chunk 0] -> Encoder(受限) -> CIF(增量) -> Decoder -> 部分文字
  [chunk 1] -> Encoder(受限) -> CIF(增量) -> Decoder -> 部分文字
  [chunk 2] -> Encoder(受限) -> CIF(增量) -> Decoder -> 部分文字
  ...
```

每个 chunk 独立走一遍 "Encoder -> CIF -> Decoder" 流程，chunk 之间通过缓存（cache）传递状态。

### 改造 1：Encoder — 双向变受限

离线版 Encoder 的每一帧能看到整段音频：

```
离线版 Encoder 注意力（双向，每帧看全部）:

        f1  f2  f3  f4  f5  f6  f7  f8
   f1 [ ok  ok  ok  ok  ok  ok  ok  ok ]
   f2 [ ok  ok  ok  ok  ok  ok  ok  ok ]
   f3 [ ok  ok  ok  ok  ok  ok  ok  ok ]
   ...                                     <- 每帧都能看到所有帧
```

流式版必须限制每帧只能看到"当前 chunk + 前 N 个 chunk + 少量前瞻"：

```
流式版 Encoder 注意力（chunk-based，受限上下文）:

chunk_size = [0, 10, 5]
  0  = 历史 chunk 数（0 表示保留全部历史）
  10 = 当前 chunk 帧数（10 帧 x 60ms = 600ms）
  5  = 前瞻帧数（5 帧 x 60ms = 300ms lookahead）

        +-- 历史chunk --+-- 当前chunk --+-- 前瞻 --+-- 未来(不可见) --+
        f1  f2 ... fN    fN+1 ... fN+10  fN+11...   fN+16 ...
   fN+1 [ok  ok ... ok    ok  ...  ok     ok  ...    XX    ...]
   fN+2 [ok  ok ... ok    ok  ...  ok     ok  ...    XX    ...]
   ...                                                XX
                                                      ^-- 完全不可见
```

具体改动：

| 组件 | 离线版 | 流式版 |
|------|--------|--------|
| Self-Attention | 双向（看全部帧） | 受限（当前 chunk + lookback + lookahead） |
| 卷积模块 | 双向（左右 padding） | **因果卷积**（只在左侧 padding，不看未来） |
| 帧间信息 | 无需额外处理 | **KV 缓存**：前面 chunk 的 key/value 传给后续 chunk |

FunASR 中对应的配置参数：

```python
encoder_chunk_look_back = 4   # Encoder self-attention 回看 4 个历史 chunk
decoder_chunk_look_back = 1   # Decoder cross-attention 回看 1 个历史 chunk
```

### 改造 2：CIF — 全局触发变增量触发

离线版 CIF 看完整个 Encoder 输出后，一次性计算所有触发点：

```
离线版 CIF:
  [f1, f2, f3, ..., f800]  ->  一次性扫描  ->  触发 120 次  ->  120 个 token
```

流式版 CIF 每个 chunk 独立处理，但需要把"未触发的余额"传递给下一个 chunk：

```
流式版 CIF (增量模式):

chunk 0: [f1..f10]  权重累加到 0.7（未触发）
         -> 输出: 0 个 token
         -> 残余权重 0.7 传给 chunk 1

chunk 1: [f11..f20] 从 0.7 继续累加
         -> f11: 0.7+0.4=1.1，触发! token 1，残余 0.1
         -> f15: 0.1+...+0.5=1.2，触发! token 2，残余 0.2
         -> 输出: 2 个 token
         -> 残余权重 0.2 传给 chunk 2

chunk 2: [f21..f30] 从 0.2 继续累加
         -> 触发 3 次
         -> 输出: 3 个 token
         -> 残余权重传给 chunk 3

...以此类推
```

这就是 cache 机制中最关键的一部分——CIF 的残余权重必须跨 chunk 传递。

### 改造 3：Decoder — 仍然并行，但范围缩小

Decoder 本身几乎不需要改：

- 离线版：接收 CIF 的全部隐藏变量，一次并行解码全部 token
- 流式版：接收当前 chunk 的 CIF 隐藏变量，一次并行解码**这个 chunk 的 token**

每个 chunk 内部仍然是 NAR 并行解码，只是解码范围从"整句"缩小到"当前 chunk 对应的几个 token"。

```
chunk 1: CIF 输出 [h1, h2] -> Decoder 并行 -> "今天"
chunk 2: CIF 输出 [h3, h4, h5] -> Decoder 并行 -> "天气真"
chunk 3: CIF 输出 [h6, h7] -> Decoder 并行 -> "不错"
```

---

## 完整流式流程

```
用户说: "今天天气真不错"

chunk 0 (0~600ms):
  audio[0:9600] -> Encoder(chunk_0, cache={})
                -> CIF(累加权重, 残余=0.6, 触发0次)
                -> 无输出
                -> cache = {encoder_kv, cif_residual=0.6}

chunk 1 (600~1200ms):
  audio[9600:19200] -> Encoder(chunk_1, cache)
                    -> CIF(从0.6继续, 触发2次)
                    -> Decoder([h1,h2]) -> "今天"
                    -> 输出: "今天"
                    -> cache = {encoder_kv, cif_residual=0.3}

chunk 2 (1200~1800ms):
  audio[19200:28800] -> Encoder(chunk_2, cache)
                     -> CIF(从0.3继续, 触发2次)
                     -> Decoder([h3,h4]) -> "天气"
                     -> 输出: "天气"
                     -> cache = {...}

chunk 3 (1800~2400ms):
  audio[28800:38400] -> Encoder(chunk_3, cache)
                     -> CIF(触发2次)
                     -> Decoder([h5,h6]) -> "真不"
                     -> 输出: "真不"
                     -> cache = {...}

chunk 4 (final):
  is_final=True -> 强制输出剩余
  -> Decoder([h7]) -> "错"
  -> 输出: "错"

最终结果: "今天" + "天气" + "真不" + "错" = "今天天气真不错"
```

---

## FunASR 中的实际代码

```python
from funasr import AutoModel

# 加载流式 Paraformer
model = AutoModel(model="paraformer-zh-streaming")

# 配置参数
chunk_size = [0, 10, 5]           # [历史chunk, 当前chunk帧数, 前瞻帧数]
encoder_chunk_look_back = 4       # Encoder 回看 4 个历史 chunk
decoder_chunk_look_back = 1       # Decoder 回看 1 个历史 chunk

# 计算每个 chunk 的采样点数
# 10 帧 x 960 采样点/帧 = 9600 采样点 = 600ms (16kHz)
chunk_stride = chunk_size[1] * 960

# 流式处理
cache = {}                        # 跨 chunk 的状态缓存
for i in range(total_chunk_num):
    speech_chunk = speech[i * chunk_stride : (i+1) * chunk_stride]
    is_final = (i == total_chunk_num - 1)

    res = model.generate(
        input=speech_chunk,
        cache=cache,              # 传入缓存 (encoder KV + CIF 残余)
        is_final=is_final,        # 最后一个 chunk 强制输出剩余 token
        chunk_size=chunk_size,
        encoder_chunk_look_back=encoder_chunk_look_back,
        decoder_chunk_look_back=decoder_chunk_look_back,
    )
    print(res)                    # 当前 chunk 的识别结果
```

`cache` 字典在每次 `model.generate()` 调用后自动更新，包含：
- Encoder 各层的 key/value 缓存
- CIF 的残余权重
- Decoder cross-attention 的历史 key/value

---

## 参数对延迟和精度的影响

### chunk_size 三元组

| 配置 | 当前 chunk | 前瞻 | 总延迟 | 精度 |
|------|-----------|------|--------|------|
| `[0, 10, 5]` | 600ms | 300ms | **900ms** | 较好（有前瞻） |
| `[0, 8, 4]` | 480ms | 240ms | **720ms** | 略低 |
| `[0, 5, 0]` | 300ms | 0ms | **300ms** | 较低（无前瞻） |
| `[0, 16, 8]` | 960ms | 480ms | **1440ms** | 最好（接近离线） |

### 为什么需要前瞻（lookahead）？

流式 Encoder 的注意力默认只看过去和当前——但语音中的协同发音（coarticulation）意味着当前帧的发音会受到**后续帧**的影响。少量前瞻（300ms）能显著提升边界处的识别精度。

```
无前瞻: Encoder 处理 "天" 时只看到 "天" 及之前 -> 可能误判
有前瞻: Encoder 处理 "天" 时还能看到后面 300ms 的 "气" -> 判断更准
```

代价是增加了 300ms 延迟（需要等前瞻部分的音频到达）。

### encoder_chunk_look_back

| 值 | 含义 | 影响 |
|---|---|---|
| 0 | 不回看，只用当前 chunk | 最快但精度最低 |
| 4（默认） | 回看 4 个历史 chunk | 精度和速度的平衡 |
| -1 | 回看全部历史 chunk | 最慢但精度最高（接近离线） |

---

## 与 AR 流式方案（Qwen3-ASR）的对比

| | Streaming Paraformer (NAR) | Qwen3-ASR (AR) |
|---|---|---|
| **chunk 内解码** | 并行（1 步出多个 token） | 串行（逐 token 生成） |
| **chunk 解码速度** | 快（~30-50ms） | 慢（token数 x 15-25ms） |
| **需要 rollback** | 不需要（CIF 自行确定边界） | 需要（边界处不确定） |
| **需要 unfixed_chunks** | 不需要 | 需要（冷启动保护） |
| **Encoder** | 受限注意力 Conformer | 全量重编码 |
| **精度** | 略低于离线版（少了未来信息） | 高（LLM 语义理解） |
| **首字延迟** | 约 600ms-1s（1-2 个 chunk） | 约 4-5s（冷启动+rollback） |
| **适合场景** | 实时对话、低延迟要求 | 高质量输出、不急于首字 |

核心区别：

- **Paraformer 流式**是把 NAR 的"一大步"拆成了"多个小步"，每个小步仍然是并行的
- **Qwen3-ASR 流式**是让 AR 在更短的音频片段上串行解码，用 rollback 处理不确定性

---

## Fun-ASR-Nano 能否实现 streaming？

### 理论上可以

Fun-ASR-Nano 也是 NAR 架构，理论上可以用同样的 chunk-based 方法：

1. 将 Encoder 改为受限注意力 + 因果卷积
2. 让解码过程逐 chunk 运行
3. 添加跨 chunk 的 cache 机制

### 实际障碍

| 障碍 | 原因 |
|------|------|
| **需要重新训练** | 因果注意力必须在训练阶段就引入，不能仅改推理代码 |
| **Encoder 架构细节未公开** | Fun-ASR-Nano 的内部结构未完全文档化 |
| **精度会下降** | 受限上下文 + 无前瞻会损失精度，需要重新调优 |
| **官方尚未发布** | 阿里语音团队可能正在做，但截至 2026 年 2 月无公开信息 |

### 对 Typeless 的建议

不需要等 Fun-ASR-Nano 的流式版本。目前的选择已经够用：

```
低延迟流式需求  ->  Streaming Paraformer (sherpa-onnx, 已集成)
高质量流式需求  ->  Qwen3-ASR 0.6B (Rust FFI, 已集成)
快速离线需求    ->  SenseVoice Nano (sherpa-onnx, 已集成)
```

如果未来阿里发布 Fun-ASR-Nano 流式版本，由于它很可能也通过 FunASR/sherpa-onnx 提供，集成工作量会很小。

---

## 参考资料

| 资料 | 说明 |
|------|------|
| [Paraformer 原始论文 (arXiv:2206.08317)](https://arxiv.org/abs/2206.08317) | CIF + GLM + MWER 的 NAR ASR 架构 |
| [FunASR GitHub](https://github.com/modelscope/FunASR) | 流式 Paraformer 的开源实现和使用示例 |
| [CIF 原始论文 (arXiv:1905.11235)](https://arxiv.org/abs/1905.11235) | Continuous Integrate-and-Fire 机制 |
| [docs/streaming-params-guide.md](./streaming-params-guide.md) | Qwen3-ASR 自回归流式参数详解（本项目） |
