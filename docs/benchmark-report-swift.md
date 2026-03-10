# ASR Pipeline 量化对比评估报告 (Swift)

*生成时间：2026-03-10 23:34*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Pipeline：Paraformer Pipeline*
*运行方式：Swift XCTest（直接复用产品代码）*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer Pipeline | 0.0852 | 20/67 | 49 | 57 | 10 | 76.3s | 0.181x |

---

## 2. 按类别 CER 汇总

| 类别 | 条数 | Paraformer Pipeline |
|------|:----:|:------:|
| chinese_long | 1 | 0.024 |
| chinese_short | 1 | 0.000 |
| code_switching | 5 | 0.136 |
| developer_corpus | 8 | 0.123 |
| english_short | 1 | 0.091 |
| long_audio | 2 | 0.065 |
| mid_sentence_pause | 2 | 0.000 |
| mixed_technical | 1 | 0.043 |
| mixed_zh_en | 1 | 0.000 |
| punctuation | 3 | 0.069 |
| real_aishell | 8 | 0.024 |
| real_ascend_codeswitching | 9 | 0.146 |
| real_codeswitching | 8 | 0.099 |
| real_conversational | 3 | 0.034 |
| real_wenetspeech | 10 | 0.085 |
| speech_rate | 2 | 0.132 |
| speech_trailing_silence | 1 | 0.000 |
| technical_numbers | 1 | 0.033 |

---

## 3. 逐条 CER 详细

| # | ID | Paraformer Pipeline | 期望文本 |
|---|-----|:------:|------|
| 1 | zh_short_01 | 0.000 | 今天天气真好。 |
| 2 | zh_long_01 | 0.024 | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，... |
| 3 | mixed_01 | 0.000 | 我今天用 Python 写了一个 API 接口。 |
| 4 | mixed_02 | 0.043 | MacBook Pro M3 芯片性能提升了百分之 40。 |
| 5 | en_short_01 | 0.091 | Hello world. |
| 6 | tech_num_01 | 0.033 | 服务器 IP 地址是 192.168.1.100，端口号 8... |
| 7 | noise_01 | 0.000 | 你好。 |
| 8 | dev_git_01 | 0.150 | 执行 git commit，修复登录 bug。 |
| 9 | dev_swift_01 | 0.000 | 定义一个 struct 叫做 UserModel。 |
| 10 | dev_rust_01 | 0.217 | 在 Rust 里面用 async await 处理并发。 |
| 11 | dev_k8s_01 | 0.324 | Kubernetes 的 pod 状态是 CrashLoop... |
| 12 | dev_api_01 | 0.043 | 调用 RESTful API 返回 JSON 格式数据。 |
| 13 | dev_db_01 | 0.094 | 执行 SQL 查询 SELECT FROM users WH... |
| 14 | dev_url_01 | 0.154 | 访问 github.com。 |
| 15 | dev_debug_01 | 0.000 | 在第 42 行设置一个 breakpoint。 |
| 16 | cs_var_01 | 0.000 | 把这个 variable 赋值给 constant。 |
| 17 | cs_build_01 | 0.300 | 在 macOS 上运行 swift build。 |
| 18 | cs_error_01 | 0.379 | 这个 error 是 null pointer except... |
| 19 | cs_deploy_01 | 0.000 | 把 Docker image push 到 registry... |
| 20 | cs_review_01 | 0.000 | 帮我 review 一下这个 pull request。 |
| 21 | punct_question_01 | 0.000 | 你今天吃饭了吗？ |
| 22 | punct_exclaim_01 | 0.000 | 太好了，我成功了。 |
| 23 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 |
| 24 | rate_fast_01 | 0.263 | 快速语音识别测试，1、2、3、4、5。 |
| 25 | rate_slow_01 | 0.000 | 慢速语音识别测试。 |
| 26 | long_30s_01 | 0.057 | 人工智能技术在过去 10 年中取得了巨大的进步。深度学习算法... |
| 27 | long_60s_01 | 0.073 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量... |
| 28 | pause_mid_01 | 0.000 | 打开终端。 |
| 29 | pause_long_01 | 0.000 | 我想要一杯咖啡。 |
| 30 | aishell_test_001 | 0.000 | 甚至出现交易几乎停滞的情况。 |
| 31 | aishell_test_002 | 0.067 | 一二线城市虽然也处于调整中。 |
| 32 | aishell_test_003 | 0.000 | 但因为聚集了过多公共资源。 |
| 33 | aishell_test_004 | 0.050 | 为了规避三四线城市明显过剩的市场风险。 |
| 34 | aishell_test_005 | 0.077 | 标杆房企必然调整市场战略。 |
| 35 | aishell_test_006 | 0.000 | 因此，土地储备至关重要。 |
| 36 | aishell_test_007 | 0.000 | 中原地产首席分析师张大伟说。 |
| 37 | aishell_test_008 | 0.000 | 一线城市土地供应量减少。 |
| 38 | conv_zh_001 | 0.040 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 |
| 39 | conv_zh_004 | 0.000 | 我想要查询我的账户余额。 |
| 40 | conv_zh_005 | 0.062 | 您好，我可以知道我的账户余额吗？ |
| 41 | ascend_cs_001 | 0.190 | No，我专业是那个 ISM，Information Syst... |
| 42 | ascend_cs_002 | 0.040 | 嗯，所以你现在还是比较 focus 在找工作这件事上。 |
| 43 | ascend_cs_003 | 0.303 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportu... |
| 44 | ascend_cs_004 | 0.071 | 嗯，I like hot pot。 |
| 45 | ascend_cs_005 | 0.082 | 所以我的我的 parents，我的妈妈是 chemistry... |
| 46 | ascend_cs_006 | 0.286 | 那个玩 basketball 的，然后我有时候有时候会邀我的... |
| 47 | ascend_cs_008 | 0.048 | 然后呃，我也喜欢 play basketball。 |
| 48 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么 major 的？ |
| 49 | ascend_cs_010 | 0.143 | 哦，我我在 UG 的时候念的是 electrical eng... |
| 50 | wenet_net_001 | 0.043 | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 |
| 51 | wenet_net_002 | 0.154 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说... |
| 52 | wenet_net_003 | 0.038 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 |
| 53 | wenet_net_004 | 0.062 | 下车后望着 30 多层的大高楼发呆。 |
| 54 | wenet_net_005 | 0.000 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊... |
| 55 | wenet_net_006 | 0.244 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不... |
| 56 | wenet_net_007 | 0.056 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是... |
| 57 | wenet_net_008 | 0.059 | 把这些劳工抓起来，送到月亮岛上去。 |
| 58 | wenet_net_009 | 0.143 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会... |
| 59 | wenet_net_010 | 0.053 | 媒体也已经报了，然后呃，债主也已经围楼了。 |
| 60 | cs_edge_001 | 0.097 | 我们团队最近在用 React 和 TypeScript 重构... |
| 61 | cs_edge_002 | 0.086 | 这个 bug 是因为 race condition 导致的 ... |
| 62 | cs_edge_003 | 0.119 | 用 Docker Compose 部署了 3 个 micro... |
| 63 | cs_edge_004 | 0.045 | 在 GitHub 上提了一个 issue，关于 perfor... |
| 64 | cs_edge_005 | 0.062 | 这个 function 的 return type 应该是 ... |
| 65 | cs_edge_006 | 0.024 | 用 Xcode 的 Instruments 做了一下 pro... |
| 66 | cs_edge_007 | 0.091 | GraphQL 的 schema 定义比 RESTful A... |
| 67 | cs_edge_008 | 0.267 | CI pipeline 跑了 30 分钟，还没通过 unit... |

---

## 4. 高 CER 条目详情 (CER > 0.20)

### Paraformer Pipeline

| # | ID | CER | 期望文本 | 实际输出 | 分析 |
|---|-----|:---:|---------|---------|------|
| 1 | cs_error_01 | 0.379 | 这个 error 是 null pointer exception。 | 这个error是no pointer it se。 | |
| 2 | dev_k8s_01 | 0.324 | Kubernetes 的 pod 状态是 CrashLoopBackOff。 | cubonates的pod状态是crash back back。 | |
| 3 | ascend_cs_003 | 0.303 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportunity。 | 深圳或者是上海这种表达城市会有更opportun。 | |
| 4 | cs_build_01 | 0.300 | 在 macOS 上运行 swift build。 | 在michael s上运行swift buil。 | |
| 5 | ascend_cs_006 | 0.286 | 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊，一起打在就是 after class 的时候。 | 那个玩玩basketball，然后我就就是稍微邀我的france一起打在就是after cast的时候。 | |
| 6 | cs_edge_008 | 0.267 | CI pipeline 跑了 30 分钟，还没通过 unit test。 | cii pipeline跑了30min还没通过unit。 | |
| 7 | rate_fast_01 | 0.263 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试12345。 | |
| 8 | wenet_net_006 | 0.244 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官。 | 这位叫peter的f b i探员，一上来就一顿。物理分析认为，阿曼达不可能吊起比他还重的女警官。 | |
| 9 | dev_rust_01 | 0.217 | 在 Rust 里面用 async await 处理并发。 | 在rust里面用a think wait处理并发。 | |
| 10 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端。第二步，输入命令。第三步，确认执行。 | |
