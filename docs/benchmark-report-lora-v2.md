# ASR Pipeline 量化对比评估报告

*生成时间：2026-03-09 12:19*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Pipeline：Paraformer Pipeline, Paraformer + Qwen3 Rewrite*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer Pipeline | 0.1008 | 15/67 | 43 | 57 | 10 | 13.1s | 0.031x |
| Paraformer + Qwen3 Rewrite | 0.1163 | 17/67 | 36 | 55 | 12 | 50.4s | 0.120x |

## 2. 按数据集/类别的平均 CER

| 类别 | N | Paraformer Pip | Paraformer + Q | 最佳 |
|------|:-:|:------:|:------:|------|
| chinese_long | 1 | **0.024** | 0.024 | Paraformer Pip |
| chinese_short | 1 | **0.000** | 0.000 | Paraformer Pip |
| code_switching | 5 | 0.144 | **0.134** | Paraformer + Q |
| developer_corpus | 8 | **0.135** | 0.151 | Paraformer Pip |
| english_short | 1 | 0.091 | **0.000** | Paraformer + Q |
| long_audio | 2 | **0.066** | 0.075 | Paraformer Pip |
| mid_sentence_pause | 2 | **0.062** | 0.062 | Paraformer Pip |
| mixed_technical | 1 | **0.000** | 0.160 | Paraformer Pip |
| mixed_zh_en | 1 | **0.050** | 0.050 | Paraformer Pip |
| punctuation | 3 | 0.111 | **0.042** | Paraformer + Q |
| real_aishell | 8 | **0.051** | 0.061 | Paraformer Pip |
| real_ascend_codeswitching | 9 | **0.149** | 0.173 | Paraformer Pip |
| real_codeswitching | 8 | **0.096** | 0.154 | Paraformer Pip |
| real_conversational | 3 | **0.074** | 0.102 | Paraformer Pip |
| real_wenetspeech | 10 | **0.092** | 0.126 | Paraformer Pip |
| speech_rate | 2 | **0.132** | 0.213 | Paraformer Pip |
| speech_trailing_silence | 1 | **0.000** | 0.000 | Paraformer Pip |
| technical_numbers | 1 | 0.267 | **0.000** | Paraformer + Q |
| **OVERALL** | 67 | **0.1008** | 0.1163 | **Paraformer Pip** |

## 3. 逐条 CER 对比

| ID | 类别 | Paraformer | Paraformer + | 最佳 |
|-----|------|:-----:|:-----:|------|
| zh_short_01 | chinese_short | **0** | **0** | Paraformer |
| zh_long_01 | chinese_long | **0.024** | 0.024 | Paraformer |
| mixed_01 | mixed_zh_en | **0.050** | 0.050 | Paraformer |
| mixed_02 | mixed_technical | **0** | 0.160 | Paraformer |
| en_short_01 | english_short | 0.091 | **0** | Paraformer |
| tech_num_01 | technical_numbers | 0.267 | **0** | Paraformer |
| noise_01 | speech_trailing_silence | **0** | **0** | Paraformer |
| dev_git_01 | developer_corpus | 0.150 | **0.100** | Paraformer |
| dev_swift_01 | developer_corpus | **0.045** | 0.045 | Paraformer |
| dev_rust_01 | developer_corpus | **0.217** | 0.217 | Paraformer |
| dev_k8s_01 | developer_corpus | **0.324** | 0.382 | Paraformer |
| dev_api_01 | developer_corpus | **0.043** | 0.087 | Paraformer |
| dev_db_01 | developer_corpus | **0.094** | 0.094 | Paraformer |
| dev_url_01 | developer_corpus | **0.154** | 0.231 | Paraformer |
| dev_debug_01 | developer_corpus | **0.050** | 0.050 | Paraformer |
| cs_var_01 | code_switching | **0** | **0** | Paraformer |
| cs_build_01 | code_switching | 0.300 | **0.250** | Paraformer |
| cs_error_01 | code_switching | **0.379** | 0.379 | Paraformer |
| cs_deploy_01 | code_switching | **0** | **0** | Paraformer |
| cs_review_01 | code_switching | **0.042** | 0.042 | Paraformer |
| punct_question_01 | punctuation | **0** | **0** | Paraformer |
| punct_exclaim_01 | punctuation | **0** | **0** | Paraformer |
| punct_list_01 | punctuation | 0.333 | **0.125** | Paraformer |
| rate_fast_01 | speech_rate | **0.263** | 0.316 | Paraformer |
| rate_slow_01 | speech_rate | **0** | 0.111 | Paraformer |
| long_30s_01 | long_audio | 0.057 | **0.046** | Paraformer |
| long_60s_01 | long_audio | **0.076** | 0.103 | Paraformer |
| pause_mid_01 | mid_sentence_pause | **0** | **0** | Paraformer |
| pause_long_01 | mid_sentence_pause | **0.125** | 0.125 | Paraformer |
| aishell_test_001 | real_aishell | **0** | **0** | Paraformer |
| aishell_test_002 | real_aishell | **0.143** | 0.143 | Paraformer |
| aishell_test_003 | real_aishell | **0** | **0** | Paraformer |
| aishell_test_004 | real_aishell | **0.105** | 0.105 | Paraformer |
| aishell_test_005 | real_aishell | **0.077** | 0.077 | Paraformer |
| aishell_test_006 | real_aishell | **0** | 0.083 | Paraformer |
| aishell_test_007 | real_aishell | **0** | **0** | Paraformer |
| aishell_test_008 | real_aishell | **0.083** | 0.083 | Paraformer |
| conv_zh_001 | real_conversational | 0.160 | **0.120** | Paraformer |
| conv_zh_004 | real_conversational | **0** | **0** | Paraformer |
| conv_zh_005 | real_conversational | **0.062** | 0.188 | Paraformer |
| ascend_cs_001 | real_ascend_codeswitching | 0.190 | **0.167** | Paraformer |
| ascend_cs_002 | real_ascend_codeswitching | **0.040** | 0.040 | Paraformer |
| ascend_cs_003 | real_ascend_codeswitching | **0.265** | 0.471 | Paraformer |
| ascend_cs_004 | real_ascend_codeswitching | 0.071 | **0** | Paraformer |
| ascend_cs_005 | real_ascend_codeswitching | **0.082** | 0.102 | Paraformer |
| ascend_cs_006 | real_ascend_codeswitching | **0.316** | 0.316 | Paraformer |
| ascend_cs_008 | real_ascend_codeswitching | **0.087** | 0.087 | Paraformer |
| ascend_cs_009 | real_ascend_codeswitching | **0.150** | 0.150 | Paraformer |
| ascend_cs_010 | real_ascend_codeswitching | **0.143** | 0.229 | Paraformer |
| wenet_net_001 | real_wenetspeech | **0.043** | 0.043 | Paraformer |
| wenet_net_002 | real_wenetspeech | **0.154** | 0.154 | Paraformer |
| wenet_net_003 | real_wenetspeech | **0.038** | 0.192 | Paraformer |
| wenet_net_004 | real_wenetspeech | 0.062 | **0** | Paraformer |
| wenet_net_005 | real_wenetspeech | **0** | 0.116 | Paraformer |
| wenet_net_006 | real_wenetspeech | **0.220** | 0.268 | Paraformer |
| wenet_net_007 | real_wenetspeech | 0.111 | **0.083** | Paraformer |
| wenet_net_008 | real_wenetspeech | **0.059** | 0.118 | Paraformer |
| wenet_net_009 | real_wenetspeech | **0.189** | 0.189 | Paraformer |
| wenet_net_010 | real_wenetspeech | **0.048** | 0.095 | Paraformer |
| cs_edge_001 | real_codeswitching | 0.097 | **0** | Paraformer |
| cs_edge_002 | real_codeswitching | 0.086 | **0** | Paraformer |
| cs_edge_003 | real_codeswitching | **0.119** | 0.143 | Paraformer |
| cs_edge_004 | real_codeswitching | **0.068** | 0.614 | Paraformer |
| cs_edge_005 | real_codeswitching | **0.062** | 0.083 | Paraformer |
| cs_edge_006 | real_codeswitching | **0.048** | 0.048 | Paraformer |
| cs_edge_007 | real_codeswitching | **0.091** | 0.212 | Paraformer |
| cs_edge_008 | real_codeswitching | 0.200 | **0.133** | Paraformer |

## 4. 推理速度对比

| Pipeline | 总音频 | 总推理 | RTF | 平均/条 |
|----------|:-----:|:-----:|:---:|:------:|
| Paraformer Pipeline | 421s | 13.1s | 0.031x | 0.20s |
| Paraformer + Qwen3 Rewrite | 421s | 50.4s | 0.120x | 0.75s |

## 5. 各 Pipeline 识别错误案例详细分析

### 5.1 Paraformer Pipeline（41 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | cs_error_01 | 0.379 | 这个error是null pointer exception。 | 这个error是no pointer it se。 | 英文词丢失: exception,null |
| 2 | punct_list_01 | 0.333 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第1步，打开终端。第2步，输入命令。第3步，确认执行。 | 数字/量词 |
| 3 | dev_k8s_01 | 0.324 | Kubernetes的pod状态是CrashLoopBackOff。 | cubonates的pod状态是crash back back。 | 英文词丢失: crashloopbackoff,kubernetes |
| 4 | ascend_cs_006 | 0.316 | 那个玩basketball的，然后我有时候有时候会邀我的friends啊，一起打… | 那个玩玩basketball，然后我就就是稍微邀我的france 1起打在就是a… | 英文词丢失: class,friends, 数字/量词 |
| 5 | cs_build_01 | 0.300 | 在macOS上运行swift build。 | 在michael s上运行swift buil。 | 英文词丢失: macos,build |
| 6 | tech_num_01 | 0.267 | 服务器IP地址是192.168.1.100，端口号8080。 | 服务器ip地址是幺92点幺68点幺点幺00端口号8080。 | 数字/量词 |
| 7 | ascend_cs_003 | 0.265 | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 | 深圳啊，或者是上海这种表达城市会有更opportun。 | 英文词丢失: opportunity |
| 8 | rate_fast_01 | 0.263 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试12345。 | 数字/量词 |
| 9 | wenet_net_006 | 0.220 | 这位叫皮特的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官… | 这位叫peter的f b i探员1上来就1顿物理分析认为阿曼达不可能吊起比他还重… | 英文词丢失: fbi, 数字/量词 |
| 10 | dev_rust_01 | 0.217 | 在Rust里面用async await处理并发。 | 在rust里面用a think wait处理并发。 | 英文词丢失: await,async |
| 11 | cs_edge_008 | 0.200 | CI pipeline跑了30分钟，还没通过unit test。 | cii pipeline跑了30分钟还没通过unit。 | 英文词丢失: ci,test, 数字/量词 |
| 12 | ascend_cs_001 | 0.190 | No，我专业是那个ISM，Information Systems Managem… | 那我就暗示那个i s n information systems managem… | 英文词丢失: no,ism |
| 13 | wenet_net_009 | 0.189 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 的的的需要啊，如果你把它当成产品的话，你会会觉得那么消费者会需要什么样？ | 同音字/近音字 |
| 14 | conv_zh_001 | 0.160 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想要了解1下我的银行账户的余额有多少？呃，谢谢。 | 数字/量词 |
| 15 | dev_url_01 | 0.154 | 访问github.com。 | 访问github点co。 | 英文词丢失: com |
| 16 | wenet_net_002 | 0.154 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有… | 数据癌症病成那样，还打着点滴，就更不可能把女主官吊了起来，说来说去，彼得认为还有… | 同音字/近音字 |
| 17 | dev_git_01 | 0.150 | 执行git commit，修复登录bug。 | 执行git commit修复登录。bu。 | 英文词丢失: bug, 标点差异 |
| 18 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么major的？ | 然后刚忘了讲1，你是念什么major？ | 同音字/近音字 |
| 19 | aishell_test_002 | 0.143 | 一二线城市虽然也处于调整中。 | 12线城市虽然也处于调整中。 | 数字/量词 |
| 20 | ascend_cs_010 | 0.143 | 哦，我我在UG的时候念的是electrical engineering。 | 哦，我我在u g的时候念的是electric engineer。 | 英文词丢失: engineering,ug,electrical |
| 21 | pause_long_01 | 0.125 | 我想要一杯咖啡。 | 我想要1杯咖啡。 | 数字/量词 |
| 22 | cs_edge_003 | 0.119 | 用Docker Compose部署了3个microservice到staging… | 用darker compose部署了3个michao service到stagi… | 英文词丢失: docker,microservice, 数字/量词 |
| 23 | wenet_net_007 | 0.111 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺，尽管孤身1人，但与好友见面时还是会爽朗1笑。 | 数字/量词 |
| 24 | aishell_test_004 | 0.105 | 为了规避三四线城市明显过剩的市场风险。 | 为了规避34线城市明显过剩的市场风险。 | 数字/量词 |
| 25 | cs_edge_001 | 0.097 | 我们团队最近在用React和TypeScript重构前端项目。 | 我们团队最近在用react和texcript重构前端项目。 | 英文词丢失: typescript |
| 26 | dev_db_01 | 0.094 | 执行SQL查询SELECT FROM users WHERE id = 1。 | 执行c ql查询select from users where i d于于。 | 英文词丢失: sql,id |
| 27 | en_short_01 | 0.091 | Hello world. | hello world。 | 标点差异 |
| 28 | cs_edge_007 | 0.091 | GraphQL的schema定义比RESTful API更灵活一些。 | graph q l的schema定义笔restful api更灵活1。 | 英文词丢失: graphql |
| 29 | ascend_cs_008 | 0.087 | 然后呃，我也喜欢play basketball。 | 然后呃我也喜play basketball。 | 标点差异 |
| 30 | cs_edge_002 | 0.086 | 这个bug是因为race condition导致的memory leak。 | 这个bug是因为race condition导致的memory li。 | 英文词丢失: leak |
| 31 | aishell_test_008 | 0.083 | 一线城市土地供应量减少。 | 1线城市土地供应量减少。 | 同音字/近音字 |
| 32 | ascend_cs_005 | 0.082 | 所以我的我的parents，我的妈妈是chemistry老师，and我的爸爸是h… | 所以我的我的parents，我的妈妈是chemistry老师，嗯，我的爸爸是hi… | 英文词丢失: and |
| 33 | aishell_test_005 | 0.077 | 标杆房企必然调整市场战略。 | 标杆房企必然调整市场占略。 | 同音字/近音字 |
| 34 | long_60s_01 | 0.076 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及… | 软件工程是1门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。它涉… | 英文词丢失: git,devops |
| 35 | ascend_cs_004 | 0.071 | 嗯，I like hot pot。 | 嗯，i d like hot pot。 | 同音字/近音字 |
| 36 | cs_edge_004 | 0.068 | 在GitHub上提了一个issue，关于performance optimiza… | 在github上提了1个约sue，关于performance optimizat… | 英文词丢失: issue |
| 37 | conv_zh_005 | 0.062 | 您好，我可以知道我的账户余额吗？ | 民好，我可以知道我的账户余额吗？ | 同音字/近音字 |
| 38 | wenet_net_004 | 0.062 | 下车后望着30多层的大高楼发呆。 | 下车后，望着30多层的大高楼发呆。 | 标点差异 |
| 39 | cs_edge_005 | 0.062 | 这个function的return type应该是Optional，而不是for… | 这个function的return tape应该是optional，而不是for… | 英文词丢失: type,unwrap |
| 40 | wenet_net_008 | 0.059 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来，送到月亮搭上去。 | 同音字/近音字 |
| 41 | long_30s_01 | 0.057 | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解… | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法，使得计算机能够处理和理… | 标点差异 |

### 5.2 Paraformer + Qwen3 Rewrite（41 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | cs_edge_004 | 0.614 | 在GitHub上提了一个issue，关于performance optimiza… | 在 GitHub 上提了 1 个关于 performance optimizat… | 数字/量词, 幻觉/冗余 |
| 2 | ascend_cs_003 | 0.471 | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 | 深圳啊，或者是上海这种表达，城市会有更多机会。 | 英文词丢失: opportunity, 截断 |
| 3 | dev_k8s_01 | 0.382 | Kubernetes的pod状态是CrashLoopBackOff。 | Cubonates 的 pod 状态是 crash, back, back。 | 英文词丢失: crashloopbackoff,kubernetes |
| 4 | cs_error_01 | 0.379 | 这个error是null pointer exception。 | 这个 error 是 no pointer，it se。 | 英文词丢失: exception,null |
| 5 | rate_fast_01 | 0.316 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试 12345 | 数字/量词, 截断 |
| 6 | ascend_cs_006 | 0.316 | 那个玩basketball的，然后我有时候有时候会邀我的friends啊，一起打… | 那个玩玩 basketball，然后我就就是稍微邀我的 France 1 起打在… | 英文词丢失: class,friends, 数字/量词 |
| 7 | wenet_net_006 | 0.268 | 这位叫皮特的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官… | 这位叫 Peter 的 FBI 探员 1 来了，就 1 顿物理分析，认为阿曼达 … | 数字/量词 |
| 8 | cs_build_01 | 0.250 | 在macOS上运行swift build。 | 在 Michael S 上运行 swift build。 | 英文词丢失: macos |
| 9 | dev_url_01 | 0.231 | 访问github.com。 | 访问 GitHub 点到 co。 | 英文词丢失: com |
| 10 | ascend_cs_010 | 0.229 | 哦，我我在UG的时候念的是electrical engineering。 | 哦我在 U-G 的时候念的是 electric engineer。 | 英文词丢失: engineering,ug,electrical |
| 11 | dev_rust_01 | 0.217 | 在Rust里面用async await处理并发。 | 在 Rust 里面用 a think wait 处理并发。 | 英文词丢失: await,async |
| 12 | cs_edge_007 | 0.212 | GraphQL的schema定义比RESTful API更灵活一些。 | graph q l 的 schema 定义，定义了 RESTful API，更灵… | 英文词丢失: graphql, 数字/量词 |
| 13 | wenet_net_003 | 0.192 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 | 当时心里想我，只要能跪我，就能站在我床上练着跪着走。 | 同音字/近音字 |
| 14 | wenet_net_009 | 0.189 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 的的的需要啊，如果你把它当成产品的话，你会会觉得那么消费者会需要什么样？ | 同音字/近音字 |
| 15 | conv_zh_005 | 0.188 | 您好，我可以知道我的账户余额吗？ | 我可以知道我的账户余额吗？ | 同音字/近音字 |
| 16 | ascend_cs_001 | 0.167 | No，我专业是那个ISM，Information Systems Managem… | 那我就暗示那个 I S N，information systems manage… | 英文词丢失: no,ism |
| 17 | mixed_02 | 0.160 | MacBook Pro M3芯片性能提升了百分之40。 | MacBook Pro M 3 芯片性能提升了 40%。 | 数字/量词 |
| 18 | wenet_net_002 | 0.154 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有… | 数据癌症病成那样，还打着点滴就更不可能把女主官吊了起来。说来说去，彼得认为还有其… | 同音字/近音字 |
| 19 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么major的？ | 然后刚忘了讲 1，你是念什么 major？ | 同音字/近音字 |
| 20 | aishell_test_002 | 0.143 | 一二线城市虽然也处于调整中。 | 12 线城市虽然也处于调整中。 | 数字/量词 |
| 21 | cs_edge_003 | 0.143 | 用Docker Compose部署了3个microservice到staging… | 用 Darker-compose 部署了 3 个 Michao service … | 英文词丢失: docker,microservice, 数字/量词 |
| 22 | cs_edge_008 | 0.133 | CI pipeline跑了30分钟，还没通过unit test。 | CI pipeline 跑了 30 分钟，还没通过 unit。 | 英文词丢失: test, 数字/量词 |
| 23 | punct_list_01 | 0.125 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第 1 步 打开终端，第 2 步 输入命令，第 3 步 确认执行。 | 数字/量词 |
| 24 | pause_long_01 | 0.125 | 我想要一杯咖啡。 | 我想要 1 杯咖啡。 | 数字/量词 |
| 25 | conv_zh_001 | 0.120 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想了解一下我的银行账户的余额有多少？谢谢。 | 数字/量词, 标点差异 |
| 26 | wenet_net_008 | 0.118 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来送到月亮搭上去。 | 标点差异 |
| 27 | wenet_net_005 | 0.116 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构… | 还有剧作模式的双线性叙事结尾，神反转等等也成为了日后《电锯惊魂》系列在剧作上的结… | 标点差异 |
| 28 | rate_slow_01 | 0.111 | 慢速语音识别测试。 | 慢速语音识别测试 | 标点差异 |
| 29 | aishell_test_004 | 0.105 | 为了规避三四线城市明显过剩的市场风险。 | 为了规避 34 线城市明显过剩的市场风险。 | 数字/量词 |
| 30 | long_60s_01 | 0.103 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及… | 软件工程是1门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科，它涉及… | 英文词丢失: devops, 数字/量词, 标点差异 |
| 31 | ascend_cs_005 | 0.102 | 所以我的我的parents，我的妈妈是chemistry老师，and我的爸爸是h… | 所以我的 parents，我的妈妈是 chemistry 老师，嗯我的爸爸是 h… | 英文词丢失: and |
| 32 | dev_git_01 | 0.100 | 执行git commit，修复登录bug。 | 执行 Git commit 修复登录 BU。 | 英文词丢失: bug, 标点差异 |
| 33 | wenet_net_010 | 0.095 | 媒体也已经报了，然后呃，债主也已经围楼了。 | 媒体也已经报了，然后呃债主也已经为楼了。 | 同音字/近音字 |
| 34 | dev_db_01 | 0.094 | 执行SQL查询SELECT FROM users WHERE id = 1。 | 执行 C QL 查询 select from users where iD 于于… | 英文词丢失: sql |
| 35 | dev_api_01 | 0.087 | 调用RESTful API返回JSON格式数据。 | 调用 RESTful API，返回 JSON 格式数。 | 标点差异 |
| 36 | ascend_cs_008 | 0.087 | 然后呃，我也喜欢play basketball。 | 然后我也喜欢 play basketball。 | 标点差异 |
| 37 | aishell_test_006 | 0.083 | 因此，土地储备至关重要。 | 因此土地储备至关重要。 | 标点差异 |
| 38 | aishell_test_008 | 0.083 | 一线城市土地供应量减少。 | 1 线城市土地供应量减少。 | 同音字/近音字 |
| 39 | wenet_net_007 | 0.083 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺，尽管孤身一人，但与好友见面时还是会爽朗 1 笑。 | 同音字/近音字 |
| 40 | cs_edge_005 | 0.083 | 这个function的return type应该是Optional，而不是for… | 这个 function 的 return tape 应该是 Optional，而… | 英文词丢失: type,unwrap |
| 41 | aishell_test_005 | 0.077 | 标杆房企必然调整市场战略。 | 标杆房企必然调整市场占略。 | 同音字/近音字 |

## 6. 综合分析与建议

### 各场景最佳 Pipeline 推荐

| 场景 | 推荐 Pipeline | CER |
|------|--------------|:---:|
| chinese_long | Paraformer Pipeline | 0.024 |
| chinese_short | Paraformer Pipeline | 0.000 |
| code_switching | Paraformer + Qwen3 Rewrite | 0.134 |
| developer_corpus | Paraformer Pipeline | 0.135 |
| english_short | Paraformer + Qwen3 Rewrite | 0.000 |
| long_audio | Paraformer Pipeline | 0.066 |
| mid_sentence_pause | Paraformer Pipeline | 0.062 |
| mixed_technical | Paraformer Pipeline | 0.000 |
| mixed_zh_en | Paraformer Pipeline | 0.050 |
| punctuation | Paraformer + Qwen3 Rewrite | 0.042 |
| real_aishell | Paraformer Pipeline | 0.051 |
| real_ascend_codeswitching | Paraformer Pipeline | 0.149 |
| real_codeswitching | Paraformer Pipeline | 0.096 |
| real_conversational | Paraformer Pipeline | 0.074 |
| real_wenetspeech | Paraformer Pipeline | 0.092 |
| speech_rate | Paraformer Pipeline | 0.132 |
| speech_trailing_silence | Paraformer Pipeline | 0.000 |
| technical_numbers | Paraformer + Qwen3 Rewrite | 0.000 |

### Pipeline 特点总结

**Paraformer Pipeline**
- 平均 CER: 0.1008
- 完美识别 (CER=0): 15/67 条
- 不准确 (CER>5%): 41/67 条
- RTF: 0.031x

**Paraformer + Qwen3 Rewrite**
- 平均 CER: 0.1163
- 完美识别 (CER=0): 17/67 条
- 不准确 (CER>5%): 41/67 条
- RTF: 0.120x

---

*报告由 `scripts/benchmark_engines.py` 自动生成*