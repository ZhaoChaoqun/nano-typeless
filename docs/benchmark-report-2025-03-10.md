# ASR Pipeline 量化对比评估报告

*生成时间：2026-03-10 16:30*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Pipeline：Qwen3-ASR (流式), Paraformer Pipeline (INT8)*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Qwen3-ASR (流式) | 0.0618 | 33/67 | 52 | 64 | 3 | 61.5s | 0.146x |
| Paraformer Pipeline (INT8) | 0.0968 | 15/67 | 45 | 57 | 10 | 13.0s | 0.031x |

## 2. 按数据集/类别的平均 CER

| 类别 | N | Qwen3-ASR | Paraformer Pip | 最佳 |
|------|:-:|:------:|:------:|------|
| chinese_long | 1 | **0.000** | 0.024 | Qwen3-ASR |
| chinese_short | 1 | **0.000** | 0.000 | Qwen3-ASR |
| code_switching | 5 | **0.042** | 0.144 | Qwen3-ASR |
| developer_corpus | 8 | **0.043** | 0.135 | Qwen3-ASR |
| english_short | 1 | **0.000** | 0.091 | Qwen3-ASR |
| long_audio | 2 | **0.008** | 0.066 | Qwen3-ASR |
| mid_sentence_pause | 2 | **0.000** | 0.062 | Qwen3-ASR |
| mixed_technical | 1 | 0.120 | **0.000** | Paraformer Pip |
| mixed_zh_en | 1 | **0.000** | 0.050 | Qwen3-ASR |
| punctuation | 3 | **0.069** | 0.069 | Qwen3-ASR |
| real_aishell | 8 | 0.096 | **0.035** | Paraformer Pip |
| real_ascend_codeswitching | 9 | **0.133** | 0.148 | Qwen3-ASR |
| real_codeswitching | 8 | **0.003** | 0.096 | Qwen3-ASR |
| real_conversational | 3 | **0.040** | 0.074 | Qwen3-ASR |
| real_wenetspeech | 10 | 0.097 | **0.092** | Paraformer Pip |
| speech_rate | 2 | **0.033** | 0.132 | Qwen3-ASR |
| speech_trailing_silence | 1 | **0.000** | 0.000 | Qwen3-ASR |
| technical_numbers | 1 | **0.100** | 0.267 | Qwen3-ASR |
| **OVERALL** | 67 | **0.0618** | 0.0968 | **Qwen3-ASR** |

## 3. 逐条 CER 对比

| ID | 类别 | Qwen3-ASR (流 | Paraformer   | 最佳 |
|-----|------|:-----:|:-----:|------|
| zh_short_01 | chinese_short | **0** | **0** | Qwen3-ASR  |
| zh_long_01 | chinese_long | **0** | 0.024 | Qwen3-ASR  |
| mixed_01 | mixed_zh_en | **0** | 0.050 | Qwen3-ASR  |
| mixed_02 | mixed_technical | 0.120 | **0** | Paraformer |
| en_short_01 | english_short | **0** | 0.091 | Qwen3-ASR  |
| tech_num_01 | technical_numbers | **0.100** | 0.267 | Qwen3-ASR  |
| noise_01 | speech_trailing_silence | **0** | **0** | Qwen3-ASR  |
| dev_git_01 | developer_corpus | **0.050** | 0.150 | Qwen3-ASR  |
| dev_swift_01 | developer_corpus | **0.045** | 0.045 | Qwen3-ASR  |
| dev_rust_01 | developer_corpus | **0.043** | 0.217 | Qwen3-ASR  |
| dev_k8s_01 | developer_corpus | **0** | 0.324 | Qwen3-ASR  |
| dev_api_01 | developer_corpus | **0** | 0.043 | Qwen3-ASR  |
| dev_db_01 | developer_corpus | 0.125 | **0.094** | Paraformer |
| dev_url_01 | developer_corpus | **0.077** | 0.154 | Qwen3-ASR  |
| dev_debug_01 | developer_corpus | **0** | 0.050 | Qwen3-ASR  |
| cs_var_01 | code_switching | 0.087 | **0** | Paraformer |
| cs_build_01 | code_switching | **0** | 0.300 | Qwen3-ASR  |
| cs_error_01 | code_switching | **0** | 0.379 | Qwen3-ASR  |
| cs_deploy_01 | code_switching | **0** | **0** | Qwen3-ASR  |
| cs_review_01 | code_switching | 0.125 | **0.042** | Paraformer |
| punct_question_01 | punctuation | **0** | **0** | Qwen3-ASR  |
| punct_exclaim_01 | punctuation | **0** | **0** | Qwen3-ASR  |
| punct_list_01 | punctuation | **0.208** | 0.208 | Qwen3-ASR  |
| rate_fast_01 | speech_rate | **0.067** | 0.263 | Qwen3-ASR  |
| rate_slow_01 | speech_rate | **0** | **0** | Qwen3-ASR  |
| long_30s_01 | long_audio | **0.005** | 0.057 | Qwen3-ASR  |
| long_60s_01 | long_audio | **0.012** | 0.076 | Qwen3-ASR  |
| pause_mid_01 | mid_sentence_pause | **0** | **0** | Qwen3-ASR  |
| pause_long_01 | mid_sentence_pause | **0** | 0.125 | Qwen3-ASR  |
| aishell_test_001 | real_aishell | **0** | **0** | Qwen3-ASR  |
| aishell_test_002 | real_aishell | **0** | 0.067 | Qwen3-ASR  |
| aishell_test_003 | real_aishell | 0.769 | **0** | Paraformer |
| aishell_test_004 | real_aishell | **0** | 0.050 | Qwen3-ASR  |
| aishell_test_005 | real_aishell | **0** | 0.077 | Qwen3-ASR  |
| aishell_test_006 | real_aishell | **0** | **0** | Qwen3-ASR  |
| aishell_test_007 | real_aishell | **0** | **0** | Qwen3-ASR  |
| aishell_test_008 | real_aishell | **0** | 0.083 | Qwen3-ASR  |
| conv_zh_001 | real_conversational | **0.120** | 0.160 | Qwen3-ASR  |
| conv_zh_004 | real_conversational | **0** | **0** | Qwen3-ASR  |
| conv_zh_005 | real_conversational | **0** | 0.062 | Qwen3-ASR  |
| ascend_cs_001 | real_ascend_codeswitching | **0.143** | 0.190 | Qwen3-ASR  |
| ascend_cs_002 | real_ascend_codeswitching | **0.040** | 0.040 | Qwen3-ASR  |
| ascend_cs_003 | real_ascend_codeswitching | 0.324 | **0.265** | Paraformer |
| ascend_cs_004 | real_ascend_codeswitching | 0.143 | **0.071** | Paraformer |
| ascend_cs_005 | real_ascend_codeswitching | **0.082** | 0.082 | Qwen3-ASR  |
| ascend_cs_006 | real_ascend_codeswitching | **0.123** | 0.304 | Qwen3-ASR  |
| ascend_cs_008 | real_ascend_codeswitching | **0.087** | 0.087 | Qwen3-ASR  |
| ascend_cs_009 | real_ascend_codeswitching | 0.200 | **0.150** | Paraformer |
| ascend_cs_010 | real_ascend_codeswitching | **0.057** | 0.143 | Qwen3-ASR  |
| wenet_net_001 | real_wenetspeech | **0** | 0.043 | Qwen3-ASR  |
| wenet_net_002 | real_wenetspeech | **0.154** | 0.154 | Qwen3-ASR  |
| wenet_net_003 | real_wenetspeech | 0.192 | **0.038** | Paraformer |
| wenet_net_004 | real_wenetspeech | **0.062** | 0.062 | Qwen3-ASR  |
| wenet_net_005 | real_wenetspeech | 0.023 | **0** | Paraformer |
| wenet_net_006 | real_wenetspeech | **0.122** | 0.220 | Qwen3-ASR  |
| wenet_net_007 | real_wenetspeech | **0.083** | 0.111 | Qwen3-ASR  |
| wenet_net_008 | real_wenetspeech | 0.176 | **0.059** | Paraformer |
| wenet_net_009 | real_wenetspeech | **0.057** | 0.189 | Qwen3-ASR  |
| wenet_net_010 | real_wenetspeech | 0.095 | **0.048** | Paraformer |
| cs_edge_001 | real_codeswitching | **0** | 0.097 | Qwen3-ASR  |
| cs_edge_002 | real_codeswitching | **0** | 0.086 | Qwen3-ASR  |
| cs_edge_003 | real_codeswitching | **0** | 0.119 | Qwen3-ASR  |
| cs_edge_004 | real_codeswitching | **0.023** | 0.068 | Qwen3-ASR  |
| cs_edge_005 | real_codeswitching | **0** | 0.062 | Qwen3-ASR  |
| cs_edge_006 | real_codeswitching | **0** | 0.048 | Qwen3-ASR  |
| cs_edge_007 | real_codeswitching | **0** | 0.091 | Qwen3-ASR  |
| cs_edge_008 | real_codeswitching | **0** | 0.200 | Qwen3-ASR  |

## 4. 推理速度对比

| Pipeline | 总音频 | 总推理 | RTF | 平均/条 |
|----------|:-----:|:-----:|:---:|:------:|
| Qwen3-ASR (流式) | 421s | 61.5s | 0.146x | 0.92s |
| Paraformer Pipeline (INT8) | 421s | 13.0s | 0.031x | 0.19s |

## 5. 各 Pipeline 识别错误案例详细分析

### 5.1 Qwen3-ASR (流式)（26 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | aishell_test_003 | 0.769 | 但因为聚集了过多公共资源。 | 但因为 | 截断 |
| 2 | ascend_cs_003 | 0.324 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportunity。 | 深圳啊，或者是上海这种比较大的城市，会有更多不听。 | 英文词丢失: opportunity |
| 3 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端。第二步，输入命令。第三步，确认执行。 | 数字/量词 |
| 4 | ascend_cs_009 | 0.200 | 然后刚忘了讲，你你是念什么 major 的？ | 然后刚刚忘了讲你你是念什么major了。 | 同音字/近音字 |
| 5 | wenet_net_003 | 0.192 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 | 当时心里想：“我只要能跪，我就能站。”我在床上练着跪着走。 | 同音字/近音字 |
| 6 | wenet_net_008 | 0.176 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来，送到梁当上上去。 | 同音字/近音字 |
| 7 | wenet_net_002 | 0.154 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有… | 数据：癌症病成那样，还打着点滴，就更不可能把女警官调了起来。说来说去，彼得认为还… | 同音字/近音字 |
| 8 | ascend_cs_001 | 0.143 | No，我专业是那个 ISM，Information Systems Manage… | 那我最爱是那个ISM Information Systems Managemen… | 英文词丢失: no, 标点差异 |
| 9 | ascend_cs_004 | 0.143 | 嗯，I like hot pot。 | 嗯，我，like hot pot。 | 英文词丢失: i |
| 10 | dev_db_01 | 0.125 | 执行 SQL 查询 SELECT FROM users WHERE id = 1… | 执行 SQL 查询：SELECT FROM users WHERE ID 等于一… | 数字/量词, 标点差异 |
| 11 | cs_review_01 | 0.125 | 帮我 review 一下这个 pull request。 | 帮我review一下这个po request。 | 英文词丢失: pull, 数字/量词 |
| 12 | ascend_cs_006 | 0.123 | 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊… | 那个玩basketball的，然后我就说：“我会邀我的friends啊，一起打在… | 数字/量词, 标点差异 |
| 13 | wenet_net_006 | 0.122 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女… | 这位叫Peter的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的… | 数字/量词 |
| 14 | mixed_02 | 0.120 | MacBook Pro M3 芯片性能提升了百分之 40。 | MacBook Pro M三芯片性能提升了百分之四十。 | 数字/量词 |
| 15 | conv_zh_001 | 0.120 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想要了解一下我的银行账户的余额有多少。呃，谢谢。 | 数字/量词 |
| 16 | tech_num_01 | 0.100 | 服务器 IP 地址是 192.168.1.100，端口号 8080。 | 服务器IP地址是192.168.1.100端口号8008。 | 标点差异 |
| 17 | wenet_net_010 | 0.095 | 媒体也已经报了，然后呃，债主也已经围楼了。 | 媒体也已经报了，然后呃，在座也已经围楼了。 | 同音字/近音字 |
| 18 | cs_var_01 | 0.087 | 把这个 variable 赋值给 constant。 | 把这个 variable 复制给 constant。 | 同音字/近音字 |
| 19 | ascend_cs_008 | 0.087 | 然后呃，我也喜欢 play basketball。 | 然后呃，我喜欢，play basketball。 | 同音字/近音字 |
| 20 | wenet_net_007 | 0.083 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺。尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 同音字/近音字 |
| 21 | ascend_cs_005 | 0.082 | 所以我的我的 parents，我的妈妈是 chemistry 老师，and 我的… | 所以我的我的parents我的妈妈是chemistry老师，然后我的爸爸是his… | 英文词丢失: and |
| 22 | dev_url_01 | 0.077 | 访问 github.com。 | 访问 GitHub 点 com。 | 标点差异 |
| 23 | rate_fast_01 | 0.067 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试：一二三四五。 | 标点差异 |
| 24 | wenet_net_004 | 0.062 | 下车后望着 30 多层的大高楼发呆。 | 下车后，望着三十多层的大高楼发呆。 | 标点差异 |
| 25 | ascend_cs_010 | 0.057 | 哦，我我在 UG 的时候念的是 electrical engineering。 | 哦，我我在UG的时候念的是electric engineering。 | 英文词丢失: electrical |
| 26 | wenet_net_009 | 0.057 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 的的需要。如果你把它当成产品的话，你会觉得那么消费者会需要什么样的。 | 同音字/近音字 |

### 5.2 Paraformer Pipeline (INT8)（40 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | cs_error_01 | 0.379 | 这个 error 是 null pointer exception。 | 这个error是no pointer it se。 | 英文词丢失: null,exception |
| 2 | dev_k8s_01 | 0.324 | Kubernetes 的 pod 状态是 CrashLoopBackOff。 | cubonates的pod状态是crash back back。 | 英文词丢失: crashloopbackoff,kubernetes |
| 3 | ascend_cs_006 | 0.304 | 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊… | 那个玩玩basketball，然后我就就是稍微邀我的france 1起打在就是a… | 英文词丢失: friends,class, 数字/量词 |
| 4 | cs_build_01 | 0.300 | 在 macOS 上运行 swift build。 | 在michael s上运行swift buil。 | 英文词丢失: build,macos |
| 5 | tech_num_01 | 0.267 | 服务器 IP 地址是 192.168.1.100，端口号 8080。 | 服务器ip地址是幺92点幺68点幺点幺00端口号8080。 | 数字/量词 |
| 6 | ascend_cs_003 | 0.265 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportunity。 | 深圳啊，或者是上海这种表达城市会有更opportun。 | 英文词丢失: opportunity |
| 7 | rate_fast_01 | 0.263 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试12345。 | 数字/量词 |
| 8 | wenet_net_006 | 0.220 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女… | 这位叫peter的f b i探员1上来就1顿物理分析认为阿曼达不可能吊起比他还重… | 英文词丢失: fbi, 数字/量词 |
| 9 | dev_rust_01 | 0.217 | 在 Rust 里面用 async await 处理并发。 | 在rust里面用a think wait处理并发。 | 英文词丢失: await,async |
| 10 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第1步，打开终端。第2步，输入命令。第3步，确认执行。 | 数字/量词 |
| 11 | cs_edge_008 | 0.200 | CI pipeline 跑了 30 分钟，还没通过 unit test。 | cii pipeline跑了30分钟还没通过unit。 | 英文词丢失: test,ci, 数字/量词 |
| 12 | ascend_cs_001 | 0.190 | No，我专业是那个 ISM，Information Systems Manage… | 那我就暗示那个i s n information systems managem… | 英文词丢失: no,ism |
| 13 | wenet_net_009 | 0.189 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 的的的需要啊，如果你把它当成产品的话，你会会觉得那么消费者会需要什么样？ | 同音字/近音字 |
| 14 | conv_zh_001 | 0.160 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想要了解1下我的银行账户的余额有多少？呃，谢谢。 | 数字/量词 |
| 15 | dev_url_01 | 0.154 | 访问 github.com。 | 访问github点co。 | 英文词丢失: com |
| 16 | wenet_net_002 | 0.154 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有… | 数据癌症病成那样，还打着点滴，就更不可能把女主官吊了起来，说来说去，彼得认为还有… | 同音字/近音字 |
| 17 | dev_git_01 | 0.150 | 执行 git commit，修复登录 bug。 | 执行git commit修复登录。bu。 | 英文词丢失: bug, 标点差异 |
| 18 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么 major 的？ | 然后刚忘了讲1，你是念什么major？ | 同音字/近音字 |
| 19 | ascend_cs_010 | 0.143 | 哦，我我在 UG 的时候念的是 electrical engineering。 | 哦，我我在u g的时候念的是electric engineer。 | 英文词丢失: engineering,electrical,ug |
| 20 | pause_long_01 | 0.125 | 我想要一杯咖啡。 | 我想要1杯咖啡。 | 数字/量词 |
| 21 | cs_edge_003 | 0.119 | 用 Docker Compose 部署了 3 个 microservice 到 … | 用darker compose部署了3个michao service到stagi… | 英文词丢失: microservice,docker, 数字/量词 |
| 22 | wenet_net_007 | 0.111 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺，尽管孤身1人，但与好友见面时还是会爽朗1笑。 | 数字/量词 |
| 23 | cs_edge_001 | 0.097 | 我们团队最近在用 React 和 TypeScript 重构前端项目。 | 我们团队最近在用react和texcript重构前端项目。 | 英文词丢失: typescript |
| 24 | dev_db_01 | 0.094 | 执行 SQL 查询 SELECT FROM users WHERE id = 1… | 执行c ql查询select from users where i d于于。 | 英文词丢失: id,sql |
| 25 | en_short_01 | 0.091 | Hello world. | hello world。 | 标点差异 |
| 26 | cs_edge_007 | 0.091 | GraphQL 的 schema 定义比 RESTful API 更灵活一些。 | graph q l的schema定义笔restful api更灵活1。 | 英文词丢失: graphql |
| 27 | ascend_cs_008 | 0.087 | 然后呃，我也喜欢 play basketball。 | 然后呃我也喜play basketball。 | 标点差异 |
| 28 | cs_edge_002 | 0.086 | 这个 bug 是因为 race condition 导致的 memory lea… | 这个bug是因为race condition导致的memory li。 | 英文词丢失: leak |
| 29 | aishell_test_008 | 0.083 | 一线城市土地供应量减少。 | 1线城市土地供应量减少。 | 同音字/近音字 |
| 30 | ascend_cs_005 | 0.082 | 所以我的我的 parents，我的妈妈是 chemistry 老师，and 我的… | 所以我的我的parents，我的妈妈是chemistry老师，嗯，我的爸爸是hi… | 英文词丢失: and |
| 31 | aishell_test_005 | 0.077 | 标杆房企必然调整市场战略。 | 标杆房企必然调整市场占略。 | 同音字/近音字 |
| 32 | long_60s_01 | 0.076 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及… | 软件工程是1门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。它涉… | 英文词丢失: git,devops |
| 33 | ascend_cs_004 | 0.071 | 嗯，I like hot pot。 | 嗯，i d like hot pot。 | 同音字/近音字 |
| 34 | cs_edge_004 | 0.068 | 在 GitHub 上提了一个 issue，关于 performance opti… | 在github上提了1个约sue，关于performance optimizat… | 英文词丢失: issue |
| 35 | aishell_test_002 | 0.067 | 一二线城市虽然也处于调整中。 | 12线城市虽然也处于调整中。 | 同音字/近音字 |
| 36 | conv_zh_005 | 0.062 | 您好，我可以知道我的账户余额吗？ | 民好，我可以知道我的账户余额吗？ | 同音字/近音字 |
| 37 | wenet_net_004 | 0.062 | 下车后望着 30 多层的大高楼发呆。 | 下车后，望着30多层的大高楼发呆。 | 标点差异 |
| 38 | cs_edge_005 | 0.062 | 这个 function 的 return type 应该是 Optional，而… | 这个function的return tape应该是optional，而不是for… | 英文词丢失: unwrap,type |
| 39 | wenet_net_008 | 0.059 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来，送到月亮搭上去。 | 同音字/近音字 |
| 40 | long_30s_01 | 0.057 | 人工智能技术在过去 10 年中取得了巨大的进步。深度学习算法使得计算机能够处理和… | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法，使得计算机能够处理和理… | 标点差异 |

## 6. 综合分析与建议

### 各场景最佳 Pipeline 推荐

| 场景 | 推荐 Pipeline | CER |
|------|--------------|:---:|
| chinese_long | Qwen3-ASR (流式) | 0.000 |
| chinese_short | Qwen3-ASR (流式) | 0.000 |
| code_switching | Qwen3-ASR (流式) | 0.042 |
| developer_corpus | Qwen3-ASR (流式) | 0.043 |
| english_short | Qwen3-ASR (流式) | 0.000 |
| long_audio | Qwen3-ASR (流式) | 0.008 |
| mid_sentence_pause | Qwen3-ASR (流式) | 0.000 |
| mixed_technical | Paraformer Pipeline (INT8) | 0.000 |
| mixed_zh_en | Qwen3-ASR (流式) | 0.000 |
| punctuation | Qwen3-ASR (流式) | 0.069 |
| real_aishell | Paraformer Pipeline (INT8) | 0.035 |
| real_ascend_codeswitching | Qwen3-ASR (流式) | 0.133 |
| real_codeswitching | Qwen3-ASR (流式) | 0.003 |
| real_conversational | Qwen3-ASR (流式) | 0.040 |
| real_wenetspeech | Paraformer Pipeline (INT8) | 0.092 |
| speech_rate | Qwen3-ASR (流式) | 0.033 |
| speech_trailing_silence | Qwen3-ASR (流式) | 0.000 |
| technical_numbers | Qwen3-ASR (流式) | 0.100 |

### Pipeline 特点总结

**Qwen3-ASR (流式)**
- 平均 CER: 0.0618
- 完美识别 (CER=0): 33/67 条
- 不准确 (CER>5%): 26/67 条
- RTF: 0.146x

**Paraformer Pipeline (INT8)**
- 平均 CER: 0.0968
- 完美识别 (CER=0): 15/67 条
- 不准确 (CER>5%): 40/67 条
- RTF: 0.031x

---

*报告由 `scripts/benchmark_engines.py` 自动生成*