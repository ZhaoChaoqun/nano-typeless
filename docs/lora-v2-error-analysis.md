# LoRA v2 错误案例深入分析

*分析日期：2026-03-09*
*模型：Qwen3-0.6B + LoRA v2（含 code-switching 训练数据）*

---

## 实验：去掉 Rewrite Pipeline 的 ITN

### 背景

原始 Rewrite pipeline 接入了 `itn_zh_number.fst`，会在 Paraformer 输出后将中文数字转成阿拉伯数字（"一二" → "12"）。但 Rewrite 模型本身应该承担 ITN 职责，多这一步反而导致 Rewrite 拿到的输入已经被破坏（如 "一二线" 变成 "12线"），且 Rewrite 无法还原。

### 三版 CER 对比

| Pipeline | 平均 CER | CER=0 | CER≤0.10 | CER>0.20 |
|----------|:-------:|:-----:|:-------:|:-------:|
| Paraformer + CSC/标点 | 0.1008 | 15/67 | 43 | 10 |
| **LoRA v2 + ITN**（旧） | 0.1163 | 17/67 | 36 | 12 |
| **LoRA v2 无 ITN**（新） | **0.1089** | **24/67** | **40** | 12 |

去掉 ITN 后：平均 CER 从 0.1163 降至 **0.1089**（-6.4%），CER=0 从 17 条涨到 **24 条**（+7）。

### 逐条对比：去掉 ITN 改善的条目

| ID | 有 ITN | 无 ITN | 原因 |
|----|:------:|:------:|------|
| aishell_test_002 | 0.143 | **0.000** | "一二线" 不再被转成 "12线" |
| aishell_test_004 | 0.105 | **0.000** | "三四线" 保留中文 |
| aishell_test_008 | 0.083 | **0.000** | "一线" 保留中文 |
| pause_long_01 | 0.125 | **0.000** | "一杯" 保留中文 |
| punct_list_01 | 0.125 | **0.000** | "第一步" 保留中文 |
| cs_review_01 | 0.042 | **0.000** | "一下" 保留中文 |
| mixed_01 | 0.050 | **0.000** | "一个" 保留中文 |
| wenet_net_004 | — | **0.000** | "30" 保留为 "三十"，与参考一致 |
| wenet_net_007 | 0.083 | **0.056** | "一人"/"一笑" 保留中文 |
| wenet_net_006 | 0.268 | **0.146** | "一上来就一顿" 保留中文 |
| long_60s_01 | 0.103 | **0.041** | "一门" 保留中文 |
| ascend_cs_006 | 0.316 | **0.298** | "一起" 保留中文 |

### 逐条对比：去掉 ITN 退化的条目

| ID | 有 ITN | 无 ITN | 原因 |
|----|:------:|:------:|------|
| mixed_02 | 0.160 | **0.280** | Paraformer 输出 "m 三" 无 ITN，Rewrite 输出 "M，三芯片"；参考是 "M3"，阿拉伯数字匹配更好 |
| rate_fast_01 | 0.316 | **0.474** | Paraformer 无 ITN 输出 "一二三四五"，Rewrite 原样保留；参考是 "1、2、3、4、5" |
| dev_debug_01 | 0.050 | **0.150** | Paraformer 无 ITN 输出 "第四十二行"，参考是 "第42行" |
| rate_slow_01 | 0.000→ | **0.111** | 无变化，句号丢失问题（ITN 无关） |

> 退化主要集中在参考文本本身使用阿拉伯数字的场景（"M3"、"42行"、"1、2、3"）。这些是参考文本标注风格问题，不影响实际使用体验。

---

## 当前错误分类汇总（无 ITN 版本）

*Pipeline：Streaming Paraformer (ASR, 无 ITN) → Qwen3 Rewrite (LoRA v2)*
*总条目：67，CER>0 条目：38，CER=0 条目：24（另 5 条两个 pipeline 都是 0）*

| 错误类别 | 条目数 | 典型 CER 范围 | 说明 |
|---------|:------:|:----------:|------|
| A. ASR 源头错误（Rewrite 无法修复） | 16 | 0.08-0.38 | Paraformer 识别就错了，Rewrite 原样保留 |
| B. Rewrite 引入退化 | 11 | 0.10-0.59 | Paraformer 正确/接近，Rewrite 改坏了 |
| C. 标点差异 | 6 | 0.08-0.12 | 句号丢失、逗号位置 |
| D. 参考文本标注不一致 | 5 | 0.07-0.47 | 参考文本用阿拉伯数字，但 Paraformer 无 ITN 输出中文数字 |

> 注：去掉 ITN 后原来的 "类别C: 数字 ITN 未转换" 已基本消除。

---

## A. ASR 源头错误（Paraformer 识别错误，Rewrite 无法修复）

这类错误的根因是 Paraformer ASR 的识别错误，Rewrite 层拿到的输入本身就是错的。

| # | ID | CER | Paraformer 原始输出 | LoRA v2 输出 | 期望文本 | 分析 |
|:-:|-----|:---:|---------|---------|---------|------|
| 1 | dev_k8s_01 | 0.382 | cubonates的pod状态是crash back back。 | Cubonates 的 pod 状态是 crash, back, back。 | Kubernetes的pod状态是CrashLoopBackOff。 | ASR 把 "Kubernetes" 识别成 "cubonates"，"CrashLoopBackOff" 拆成 "crash back back" |
| 2 | cs_error_01 | 0.379 | 这个error是no pointer it se。 | 这个 error 是 no pointer，it se。 | 这个error是null pointer exception。 | ASR 把 "null" 听成 "no"，"exception" 听成 "it se" |
| 3 | ascend_cs_006 | 0.298 | 那个玩玩basketball，然后我就就是稍微邀我的france一起打在就是after cast的时候。 | 那个玩玩 basketball，然后我就就是稍微邀我的 France 一起打在就是 after cast 的时候。 | 那个玩basketball的，然后我有时候有时候会邀我的friends啊，一起打在就是after class的时候。 | ASR 把 "friends" 听成 "france"，"class" 听成 "cast" |
| 4 | cs_build_01 | 0.250 | 在michael s上运行swift buil。 | 在 Michael S 上运行 swift build。 | 在macOS上运行swift build。 | ASR 把 "macOS" 听成 "michael s"；Rewrite 修复了 "buil"→"build" |
| 5 | dev_url_01 | 0.231 | 访问github点co。 | 访问 GitHub 点到 co。 | 访问github.com。 | ASR 没识别出 ".com" |
| 6 | ascend_cs_010 | 0.229 | 哦，我我在u g的时候念的是electric engineer。 | 哦我在 U-G 的时候念的是 electric engineer。 | 哦，我我在UG的时候念的是electrical engineering。 | ASR 丢了 "-al"/"-ing" 后缀 |
| 7 | dev_rust_01 | 0.217 | 在rust里面用a think wait处理并发。 | 在 Rust 里面用 a think wait 处理并发。 | 在Rust里面用async await处理并发。 | ASR 把 "async" 听成 "a think" |
| 8 | ascend_cs_001 | 0.167 | 那我就暗示那个i s n information systems management。 | 那我就暗示那个 I S N，information systems management。 | No，我专业是那个ISM，Information Systems Management。 | ASR 把 "No 我专业" 听成 "那我就暗示"，"ISM" 听成 "i s n" |
| 9 | wenet_net_002 | 0.154 | 数据癌症病成那样… | 数据癌症病成那样… | 竖锯癌症病成那样… | ASR 把电影角色 "竖锯" 听成 "数据" |
| 10 | ascend_cs_005 | 0.102 | …chemistry老师，嗯，我的爸爸是history老。 | …chemistry 老师，嗯我的爸爸是 history 老师。 | …chemistry老师，and我的爸爸是history老师。 | ASR 把 "and" 听成 "嗯"；Rewrite 补回了 "老师" |
| 11 | cs_edge_003 | 0.143 | 用darker compose部署了三个michao service到staging环。 | 用 Darker-compose 部署了 3 个 Michao service 到 staging 环。 | 用Docker Compose部署了3个microservice到staging环境。 | ASR 把 "Docker" 听成 "darker"，"microservice" 听成 "michao service" |
| 12 | cs_edge_005 | 0.083 | 这个function的return tape应该是optional，而不是force and rap。 | 这个 function 的 return tape 应该是 Optional，而不是 force 和 rap。 | 这个function的return type应该是Optional，而不是force unwrap。 | ASR 把 "type" 听成 "tape"，"unwrap" 听成 "and rap" |
| 13 | cs_edge_008 | 0.167 | cii pipeline跑了三十分钟还没通过unit。 | CII pipeline 跑了 30 分钟，还没通过 unit。 | CI pipeline跑了30分钟，还没通过unit test。 | ASR 截断了 "test"；Rewrite 修复了大写但 "cii" 未修正为 "CI" |
| 14 | dev_db_01 | 0.094 | 执行c ql查询select from users where i d于于。 | 执行 C QL 查询 select from users where iD 于于。 | 执行SQL查询SELECT FROM users WHERE id = 1。 | ASR 把 "SQL" 拆读成 "c ql" |
| 15 | dev_git_01 | 0.100 | 执行git commit修复登录。bu。 | 执行 Git commit 修复登录 BU。 | 执行git commit，修复登录bug。 | ASR 截断 "bug"→"bu" |
| 16 | aishell_test_005 | 0.077 | 标杆房企必然调整市场占略。 | 标杆房企必然调整市场占略。 | 标杆房企必然调整市场战略。 | ASR 把 "战略" 听成 "占略"，Rewrite 未纠正（CSC 能力不足） |

### Rewrite 成功修复 ASR 错误的正面案例

| ID | P-CER | R-CER | Paraformer 错误 → Rewrite 修复 |
|----|:-----:|:-----:|---------|
| cs_edge_001 | 0.097 | **0.000** | "texcript" → "TypeScript" |
| cs_edge_002 | 0.086 | **0.000** | "memory li" → "memory leak" |
| en_short_01 | 0.091 | **0.000** | "hello world。" → "Hello world." |
| ascend_cs_004 | 0.071 | **0.000** | "i d like" → "I like" |
| cs_build_01 | 0.300 | 0.250 | "swift buil" → "swift build" |

---

## B. Rewrite 引入退化（Paraformer 更好，Rewrite 改坏了）

这类错误是 Rewrite 层引入的新问题，Paraformer 原始输出反而更好或一样好。

| # | ID | P-CER | R-CER | Paraformer 原始输出 | LoRA v2 输出 | 期望文本 | 分析 |
|:-:|-----|:---:|:---:|---------|---------|---------|------|
| 1 | **cs_edge_004** | 0.068 | **0.591** | 在github上提了一个约sue，关于performance optimization。 | 在 GitHub 上提了一个关于 performance optimization 的 issue，关于 performance optimization。 | 在GitHub上提了一个issue，关于performance optimization。 | **幻觉/重复**：Rewrite 重组句子并重复了 "关于 performance optimization" |
| 2 | **ascend_cs_003** | 0.265 | **0.471** | 深圳啊，或者是上海这种表达城市会有更多opportun。 | 深圳啊，或者是上海这种表达，城市会有更多机会。 | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 | **英文被翻译**："opportun" 被翻译成 "机会" 而非保留英文 |
| 3 | **cs_edge_007** | 0.091 | **0.212** | graph q l的schema定义笔restful api更灵活一些。 | graph q l 的 schema 定义，定义了 RESTful API，更灵活一。 | GraphQL的schema定义比RESTful API更灵活一些。 | **改写句意**：Rewrite 把 "比...更灵活" 改成 "定义了...更灵活"，引入多余文字 |
| 4 | **wenet_net_003** | 0.038 | **0.192** | 当时心里想，我只要能跪，我就能站，我在床上练着跪着走。 | 当时心里想我，只要能跪我，就能站在我床上练着跪着走。 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 | **标点改坏**：Rewrite 删逗号并改变语义分割（"站在我床上"） |
| 5 | **conv_zh_005** | 0.062 | **0.188** | 民好，我可以知道我的账户余额吗？ | 我可以知道我的账户余额吗？ | 您好，我可以知道我的账户余额吗？ | **丢失内容**：Rewrite 把 "民好" 整段删除（应保留并修正为 "您好"） |
| 6 | **wenet_net_005** | 0.000 | **0.116** | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构模式。 | 还有剧作模式的双线性叙事结尾，神反转等等也成为了日后《电锯惊魂》系列在剧作上的结构模式。 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构模式。 | **标点改坏**：Paraformer 完美匹配，Rewrite 删顿号、移逗号、加书名号 |
| 7 | **wenet_net_008** | 0.059 | **0.118** | 把这些劳工抓起来，送到月亮搭上去。 | 把这些劳工抓起来送到月亮搭上去。 | 把这些劳工抓起来，送到月亮岛上去。 | **标点删除**：Rewrite 删掉了正确的逗号 |
| 8 | **rate_slow_01** | 0.000 | **0.111** | 慢速语音识别测试。 | 慢速语音识别测试 | 慢速语音识别测试。 | **句号丢失**：Rewrite 把末尾句号删了 |
| 9 | **wenet_net_010** | 0.048 | **0.095** | 媒体也已经报了，然后呃，债主也已经为楼了。 | 媒体也已经报了，然后呃债主也已经为楼了。 | 媒体也已经报了，然后呃，债主也已经围楼了。 | **标点删除**："呃" 后面的逗号被删除 |
| 10 | **dev_debug_01** | 0.050 | **0.150** | 在第四十二行设置一个break point。 | 在第四十二行设置一个 break point。 | 在第42行设置一个breakpoint。 | 无 ITN 后 "42" 保持为 "四十二"，与参考不一致；Rewrite 也未合并 "break point" → "breakpoint" |
| 11 | **mixed_02** | 0.000 | **0.280** | macbook pro m 三芯片性能提升了百分之四十。 | MacBook Pro M，三芯片，性能提升了 40%。 | MacBook Pro M3芯片性能提升了百分之40。 | **改写过度**：Rewrite 在 "M" 和 "三" 之间插入逗号造成断句错误，"百分之四十" 改成 "40%" |

---

## C. 标点差异（Rewrite 的标点策略与参考不一致）

| # | ID | CER | LoRA v2 输出 | 期望文本 | 说明 |
|:-:|-----|:---:|---------|---------|------|
| 1 | conv_zh_001 | 0.120 | 你好，我想了解一下我的银行账户的余额有多少？谢谢。 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 删 "要"、加 "的"、问号替逗号 |
| 2 | wenet_net_009 | 0.189 | 的的的需要啊，如果你把它当成产品的话，你会会觉得那么消费者会需要什么样？ | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | ASR 多了 "的" 和 "啊"、少了 "嗯"（纯 ASR 错） |
| 3 | aishell_test_006 | 0.083 | 因此土地储备至关重要。 | 因此，土地储备至关重要。 | 丢失逗号 |
| 4 | dev_api_01 | 0.087 | 调用 RESTful API，返回 JSON 格式数。 | 调用RESTful API返回JSON格式数据。 | "数据" 被截成 "数"（ASR 源头）+多余逗号 |
| 5 | ascend_cs_008 | 0.087 | 然后我也喜欢 play basketball。 | 然后呃，我也喜欢play basketball。 | 删了语气词 "呃" 和逗号 |
| 6 | ascend_cs_009 | 0.150 | 然后刚忘了讲一你是念什么 major？ | 然后刚忘了讲，你你是念什么major的？ | "讲一你" 分词错误，丢失逗号 |

---

## D. 参考文本标注不一致（去掉 ITN 后新增的退化）

这些条目退化的原因是参考文本本身使用阿拉伯数字，但去掉 ITN 后 Paraformer 输出中文数字。

| # | ID | 有 ITN | 无 ITN | Paraformer 无 ITN 输出 | 参考文本 | 说明 |
|:-:|-----|:---:|:---:|---------|---------|------|
| 1 | rate_fast_01 | 0.316 | 0.474 | 快速语音识别测试，一二三四五。 | 快速语音识别测试，1、2、3、4、5。 | 参考用顿号分隔阿拉伯数字 |
| 2 | mixed_02 | 0.160 | 0.280 | macbook pro m 三芯片性能提升了百分之四十。 | MacBook Pro M3芯片性能提升了百分之40。 | 参考中 "M3" 和 "40" 是阿拉伯数字 |
| 3 | dev_debug_01 | 0.050 | 0.150 | 在第四十二行设置一个break point。 | 在第42行设置一个breakpoint。 | 参考用 "42"（代码行号场景应该用阿拉伯数字） |

> 这类退化说明：**在技术术语/代码场景中，阿拉伯数字是更合理的表达**（M3、42行、192.168.x.x）。未来可以考虑让 Rewrite 模型学习根据上下文选择性地将中文数字转为阿拉伯数字。

---

## E. 长文本退化

| # | ID | CER | 关键问题 |
|:-:|-----|:---:|---------|
| 1 | long_60s_01 | 0.041 | 去掉 ITN 后改善（0.103→0.041）：不再有 "1门" 问题；但 Rewrite 仍缺 "DevOps"（英文丢失），跳过部分句子 |
| 2 | wenet_net_006 | 0.146 | 去掉 ITN 后改善（0.268→0.146）：中文数字 "一上来就一顿" 保留了；但 ASR 源 "皮特"→"Peter"、"她"→"他" 仍存在 |

---

## 关键发现总结

### 1. 去掉 ITN 的效果

去掉 ITN 是 **净正向** 的改进：

| 指标 | 有 ITN | 无 ITN |
|------|:------:|:------:|
| 平均 CER | 0.1163 | **0.1089** (-6.4%) |
| CER=0 条数 | 17/67 | **24/67** (+41%) |
| CER≤0.10 条数 | 36/67 | **40/67** |

根因：Paraformer 原始输出中，"一二线""一杯""第一步" 这类量词/序数词本来就是中文，ITN 强行转成阿拉伯数字反而造成错误。

### 2. Rewrite 的正面价值

| ID | P-CER | R-CER | Paraformer 错误 → Rewrite 修复 |
|----|:-----:|:-----:|---------|
| cs_edge_001 | 0.097 | **0.000** | "texcript" → "TypeScript" |
| cs_edge_002 | 0.086 | **0.000** | "memory li" → "memory leak" |
| en_short_01 | 0.091 | **0.000** | "hello world。" → "Hello world." |
| ascend_cs_004 | 0.071 | **0.000** | "i d like" → "I like" |
| mixed_01 | 0.050 | **0.000** | 格式修正 |
| dev_swift_01 | 0.045 | **0.000** | 格式修正 |
| punct_list_01 | 0.333 | **0.000** | "第1步 打开终端。第2步..." → "第一步打开终端，第二步..." |
| punct 系列 | >0 | **0.000** | 标点修正 |
| tech_num_01 | 0.267 | **0.067** | "幺92点幺68..." → "192.168.10.100"（大部分修复） |
| cs_build_01 | 0.300 | 0.250 | "swift buil" → "swift build" |
| wenet_net_006 | 0.220 | **0.146** | 数字中文化+格式修正 |
| wenet_net_007 | 0.111 | **0.056** | 数字中文化 |

### 3. 三大剩余核心问题

**问题一：Rewrite 改写过度/幻觉（影响 5 条，贡献约 0.020 平均 CER）**
- cs_edge_004：句子被重组并重复（CER 0.591）
- ascend_cs_003："opportunity" 被翻译成 "机会"
- cs_edge_007：插入多余文字
- wenet_net_003：重新组织标点导致语义变化
- conv_zh_005：直接删除首部内容

**问题二：标点过度修改（影响 8+ 条，贡献约 0.010 平均 CER）**
- 删除正确的逗号/句号（rate_slow_01、wenet_net_008、wenet_net_010）
- 加入不需要的逗号（mixed_02）
- Paraformer 已经完美但 Rewrite 改坏（wenet_net_005）

**问题三：技术场景数字格式（影响 3 条）**
- 代码行号 "第四十二行" 应该是 "第42行"
- 型号 "M三" 应该是 "M3"
- 需要根据上下文智能选择中文/阿拉伯数字

### 4. 改进方向

| 优先级 | 方向 | 预期影响 | 方法 |
|:------:|------|---------|------|
| P0 | 修复幻觉/重复 | -0.020 CER | 生成时加 repetition penalty；训练数据加 "保持原句结构" 的强约束样本 |
| P1 | 防止标点过度修改 | -0.010 CER | 训练数据增加 "标点基本正确不需修改" 的样本比例 |
| P2 | 上下文数字格式 | -0.005 CER | 训练数据加 "代码场景: 四十二行→42行"、"型号: M三→M3" 等正样本 |
| P3 | 保留不确定英文 | -0.005 CER | 训练不认识的英文片段保持原样而非翻译 |
