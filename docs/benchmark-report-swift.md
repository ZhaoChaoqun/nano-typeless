# ASR Pipeline 量化对比评估报告 (Swift)

*生成时间：2026-03-10 22:24*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Pipeline：Paraformer + Cloud Rewrite*
*运行方式：Swift XCTest（直接复用产品代码）*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer + Cloud Rewrite | 0.1589 | 5/67 | 24 | 51 | 16 | 201.3s | 0.478x |

---

## 2. 按类别 CER 汇总

| 类别 | 条数 | Paraformer + Cloud Rewrite |
|------|:----:|:------:|
| chinese_long | 1 | 0.098 |
| chinese_short | 1 | 0.286 |
| code_switching | 5 | 0.137 |
| developer_corpus | 8 | 0.160 |
| english_short | 1 | 0.364 |
| long_audio | 2 | 0.086 |
| mid_sentence_pause | 2 | 0.225 |
| mixed_technical | 1 | 0.240 |
| mixed_zh_en | 1 | 0.150 |
| punctuation | 3 | 0.199 |
| real_aishell | 8 | 0.077 |
| real_ascend_codeswitching | 9 | 0.178 |
| real_codeswitching | 8 | 0.094 |
| real_conversational | 3 | 0.123 |
| real_wenetspeech | 10 | 0.138 |
| speech_rate | 2 | 0.156 |
| speech_trailing_silence | 1 | 0.667 |
| technical_numbers | 1 | 0.633 |

---

## 3. 逐条 CER 详细

| # | ID | Paraformer + Cloud Rewrite | 期望文本 |
|---|-----|:------:|------|
| 1 | zh_short_01 | 0.286 | 今天天气真好。 |
| 2 | zh_long_01 | 0.098 | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，... |
| 3 | mixed_01 | 0.150 | 我今天用 Python 写了一个 API 接口。 |
| 4 | mixed_02 | 0.240 | MacBook Pro M3 芯片性能提升了百分之 40。 |
| 5 | en_short_01 | 0.364 | Hello world. |
| 6 | tech_num_01 | 0.633 | 服务器 IP 地址是 192.168.1.100，端口号 8... |
| 7 | noise_01 | 0.667 | 你好。 |
| 8 | dev_git_01 | 0.150 | 执行 git commit，修复登录 bug。 |
| 9 | dev_swift_01 | 0.000 | 定义一个 struct 叫做 UserModel。 |
| 10 | dev_rust_01 | 0.261 | 在 Rust 里面用 async await 处理并发。 |
| 11 | dev_k8s_01 | 0.206 | Kubernetes 的 pod 状态是 CrashLoop... |
| 12 | dev_api_01 | 0.174 | 调用 RESTful API 返回 JSON 格式数据。 |
| 13 | dev_db_01 | 0.094 | 执行 SQL 查询 SELECT FROM users WH... |
| 14 | dev_url_01 | 0.154 | 访问 github.com。 |
| 15 | dev_debug_01 | 0.238 | 在第 42 行设置一个 breakpoint。 |
| 16 | cs_var_01 | 0.043 | 把这个 variable 赋值给 constant。 |
| 17 | cs_build_01 | 0.300 | 在 macOS 上运行 swift build。 |
| 18 | cs_error_01 | 0.138 | 这个 error 是 null pointer except... |
| 19 | cs_deploy_01 | 0.077 | 把 Docker image push 到 registry... |
| 20 | cs_review_01 | 0.125 | 帮我 review 一下这个 pull request。 |
| 21 | punct_question_01 | 0.250 | 你今天吃饭了吗？ |
| 22 | punct_exclaim_01 | 0.222 | 太好了，我成功了。 |
| 23 | punct_list_01 | 0.125 | 第一步打开终端，第二步输入命令，第三步确认执行。 |
| 24 | rate_fast_01 | 0.200 | 快速语音识别测试，1、2、3、4、5。 |
| 25 | rate_slow_01 | 0.111 | 慢速语音识别测试。 |
| 26 | long_30s_01 | 0.073 | 人工智能技术在过去 10 年中取得了巨大的进步。深度学习算法... |
| 27 | long_60s_01 | 0.100 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量... |
| 28 | pause_mid_01 | 0.200 | 打开终端。 |
| 29 | pause_long_01 | 0.250 | 我想要一杯咖啡。 |
| 30 | aishell_test_001 | 0.071 | 甚至出现交易几乎停滞的情况。 |
| 31 | aishell_test_002 | 0.071 | 一二线城市虽然也处于调整中。 |
| 32 | aishell_test_003 | 0.077 | 但因为聚集了过多公共资源。 |
| 33 | aishell_test_004 | 0.000 | 为了规避三四线城市明显过剩的市场风险。 |
| 34 | aishell_test_005 | 0.077 | 标杆房企必然调整市场战略。 |
| 35 | aishell_test_006 | 0.167 | 因此，土地储备至关重要。 |
| 36 | aishell_test_007 | 0.071 | 中原地产首席分析师张大伟说。 |
| 37 | aishell_test_008 | 0.083 | 一线城市土地供应量减少。 |
| 38 | conv_zh_001 | 0.160 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 |
| 39 | conv_zh_004 | 0.083 | 我想要查询我的账户余额。 |
| 40 | conv_zh_005 | 0.125 | 您好，我可以知道我的账户余额吗？ |
| 41 | ascend_cs_001 | 0.190 | No，我专业是那个 ISM，Information Syst... |
| 42 | ascend_cs_002 | 0.120 | 嗯，所以你现在还是比较 focus 在找工作这件事上。 |
| 43 | ascend_cs_003 | 0.176 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportu... |
| 44 | ascend_cs_004 | 0.429 | 嗯，I like hot pot。 |
| 45 | ascend_cs_005 | 0.122 | 所以我的我的 parents，我的妈妈是 chemistry... |
| 46 | ascend_cs_006 | 0.211 | 那个玩 basketball 的，然后我有时候有时候会邀我的... |
| 47 | ascend_cs_008 | 0.087 | 然后呃，我也喜欢 play basketball。 |
| 48 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么 major 的？ |
| 49 | ascend_cs_010 | 0.114 | 哦，我我在 UG 的时候念的是 electrical eng... |
| 50 | wenet_net_001 | 0.000 | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 |
| 51 | wenet_net_002 | 0.173 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说... |
| 52 | wenet_net_003 | 0.115 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 |
| 53 | wenet_net_004 | 0.125 | 下车后望着 30 多层的大高楼发呆。 |
| 54 | wenet_net_005 | 0.093 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊... |
| 55 | wenet_net_006 | 0.220 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不... |
| 56 | wenet_net_007 | 0.167 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是... |
| 57 | wenet_net_008 | 0.000 | 把这些劳工抓起来，送到月亮岛上去。 |
| 58 | wenet_net_009 | 0.343 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会... |
| 59 | wenet_net_010 | 0.143 | 媒体也已经报了，然后呃，债主也已经围楼了。 |
| 60 | cs_edge_001 | 0.000 | 我们团队最近在用 React 和 TypeScript 重构... |
| 61 | cs_edge_002 | 0.029 | 这个 bug 是因为 race condition 导致的 ... |
| 62 | cs_edge_003 | 0.190 | 用 Docker Compose 部署了 3 个 micro... |
| 63 | cs_edge_004 | 0.159 | 在 GitHub 上提了一个 issue，关于 perfor... |
| 64 | cs_edge_005 | 0.167 | 这个 function 的 return type 应该是 ... |
| 65 | cs_edge_006 | 0.048 | 用 Xcode 的 Instruments 做了一下 pro... |
| 66 | cs_edge_007 | 0.061 | GraphQL 的 schema 定义比 RESTful A... |
| 67 | cs_edge_008 | 0.100 | CI pipeline 跑了 30 分钟，还没通过 unit... |

---

## 4. 高 CER 条目详情 (CER > 0.20)

### Paraformer + Cloud Rewrite

| # | ID | CER | 期望文本 | 实际输出 | 分析 |
|---|-----|:---:|---------|---------|------|
| 1 | noise_01 | 0.667 | 你好。 | 好你 | |
| 2 | tech_num_01 | 0.633 | 服务器 IP 地址是 192.168.1.100，端口号 8080。 | 服务器ip地址是幺九二点幺六八点幺点幺零零端口号八千零八十 | |
| 3 | ascend_cs_004 | 0.429 | 嗯，I like hot pot。 | umlikelikehotpott | |
| 4 | en_short_01 | 0.364 | Hello world. | loloworld | |
| 5 | wenet_net_009 | 0.343 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 如果你把它当成产品的话，您会觉得消费者需要什么样的？ | |
| 6 | cs_build_01 | 0.300 | 在 macOS 上运行 swift build。 | 在michaels上运行swiftbuild | |
| 7 | zh_short_01 | 0.286 | 今天天气真好。 | 天天气真好好 | |
| 8 | dev_rust_01 | 0.261 | 在 Rust 里面用 async await 处理并发。 | 在rust里面用athinkwait处理并发 | |
| 9 | punct_question_01 | 0.250 | 你今天吃饭了吗？ | 你今今天吃饭了吗 | |
| 10 | pause_long_01 | 0.250 | 我想要一杯咖啡。 | 我想要要杯咖啡啡 | |
| 11 | mixed_02 | 0.240 | MacBook Pro M3 芯片性能提升了百分之 40。 | maacbookproom三芯片性能提升了百分之四十 | |
| 12 | dev_debug_01 | 0.238 | 在第 42 行设置一个 breakpoint。 | 在第四十二行设置一个breakpointpoint | |
| 13 | punct_exclaim_01 | 0.222 | 太好了，我成功了。 | 太好了我成功了 | |
| 14 | wenet_net_006 | 0.220 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官。 | 这位叫Peter的FBI探员一上来就进行一番物理分析，认为阿曼达不可能举起比她还重的女警官。 | |
| 15 | ascend_cs_006 | 0.211 | 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊，一起打在就是 after class 的时候。 | 那个玩basketball然后我就说稍微邀我的friends啊一起打在就是aftercass的时候 | |
| 16 | dev_k8s_01 | 0.206 | Kubernetes 的 pod 状态是 CrashLoopBackOff。 | cubonates的pod状态是crashroombackoff | |
