# ASR Pipeline 量化对比评估报告

*生成时间：2026-03-09 03:12*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Pipeline：Paraformer Pipeline, Paraformer + Qwen3 Rewrite*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer Pipeline | 0.1008 | 15/67 | 43 | 57 | 10 | 12.8s | 0.030x |
| Paraformer + Qwen3 Rewrite | 9.9043 | 0/67 | 0 | 0 | 67 | 178.2s | 0.423x |

## 2. 按数据集/类别的平均 CER

| 类别 | N | Paraformer Pip | Paraformer + Q | 最佳 |
|------|:-:|:------:|:------:|------|
| chinese_long | 1 | **0.024** | 3.878 | Paraformer Pip |
| chinese_short | 1 | **0.000** | 29.000 | Paraformer Pip |
| code_switching | 5 | **0.144** | 6.714 | Paraformer Pip |
| developer_corpus | 8 | **0.135** | 7.115 | Paraformer Pip |
| english_short | 1 | **0.091** | 8.273 | Paraformer Pip |
| long_audio | 2 | **0.066** | 1.925 | Paraformer Pip |
| mid_sentence_pause | 2 | **0.062** | 28.050 | Paraformer Pip |
| mixed_technical | 1 | **0.000** | 10.240 | Paraformer Pip |
| mixed_zh_en | 1 | **0.050** | 22.000 | Paraformer Pip |
| punctuation | 3 | **0.111** | 20.218 | Paraformer Pip |
| real_aishell | 8 | **0.051** | 13.945 | Paraformer Pip |
| real_ascend_codeswitching | 9 | **0.149** | 6.558 | Paraformer Pip |
| real_codeswitching | 8 | **0.096** | 3.615 | Paraformer Pip |
| real_conversational | 3 | **0.074** | 10.305 | Paraformer Pip |
| real_wenetspeech | 10 | **0.092** | 5.816 | Paraformer Pip |
| speech_rate | 2 | **0.132** | 19.216 | Paraformer Pip |
| speech_trailing_silence | 1 | **0.000** | 43.667 | Paraformer Pip |
| technical_numbers | 1 | **0.267** | 8.433 | Paraformer Pip |
| **OVERALL** | 67 | **0.1008** | 9.9043 | **Paraformer Pip** |

## 3. 逐条 CER 对比

| ID | 类别 | Paraformer | Paraformer + | 最佳 |
|-----|------|:-----:|:-----:|------|
| zh_short_01 | chinese_short | **0** | 29.0 | Paraformer |
| zh_long_01 | chinese_long | **0.024** | 3.9 | Paraformer |
| mixed_01 | mixed_zh_en | **0.050** | 22.0 | Paraformer |
| mixed_02 | mixed_technical | **0** | 10.2 | Paraformer |
| en_short_01 | english_short | **0.091** | 8.3 | Paraformer |
| tech_num_01 | technical_numbers | **0.267** | 8.4 | Paraformer |
| noise_01 | speech_trailing_silence | **0** | 43.7 | Paraformer |
| dev_git_01 | developer_corpus | **0.150** | 7.7 | Paraformer |
| dev_swift_01 | developer_corpus | **0.045** | 7.3 | Paraformer |
| dev_rust_01 | developer_corpus | **0.217** | 8.8 | Paraformer |
| dev_k8s_01 | developer_corpus | **0.324** | 3.1 | Paraformer |
| dev_api_01 | developer_corpus | **0.043** | 10.7 | Paraformer |
| dev_db_01 | developer_corpus | **0.094** | 4.5 | Paraformer |
| dev_url_01 | developer_corpus | **0.154** | 8.7 | Paraformer |
| dev_debug_01 | developer_corpus | **0.050** | 6.2 | Paraformer |
| cs_var_01 | code_switching | **0** | 6.3 | Paraformer |
| cs_build_01 | code_switching | **0.300** | 11.8 | Paraformer |
| cs_error_01 | code_switching | **0.379** | 4.3 | Paraformer |
| cs_deploy_01 | code_switching | **0** | 5.7 | Paraformer |
| cs_review_01 | code_switching | **0.042** | 5.4 | Paraformer |
| punct_question_01 | punctuation | **0** | 34.1 | Paraformer |
| punct_exclaim_01 | punctuation | **0** | 13.8 | Paraformer |
| punct_list_01 | punctuation | **0.333** | 12.8 | Paraformer |
| rate_fast_01 | speech_rate | **0.263** | 7.2 | Paraformer |
| rate_slow_01 | speech_rate | **0** | 31.2 | Paraformer |
| long_30s_01 | long_audio | **0.057** | 1.000 | Paraformer |
| long_60s_01 | long_audio | **0.076** | 2.9 | Paraformer |
| pause_mid_01 | mid_sentence_pause | **0** | 40.6 | Paraformer |
| pause_long_01 | mid_sentence_pause | **0.125** | 15.5 | Paraformer |
| aishell_test_001 | real_aishell | **0** | 9.6 | Paraformer |
| aishell_test_002 | real_aishell | **0.143** | 14.6 | Paraformer |
| aishell_test_003 | real_aishell | **0** | 10.3 | Paraformer |
| aishell_test_004 | real_aishell | **0.105** | 7.1 | Paraformer |
| aishell_test_005 | real_aishell | **0.077** | 18.2 | Paraformer |
| aishell_test_006 | real_aishell | **0** | 22.0 | Paraformer |
| aishell_test_007 | real_aishell | **0** | 9.6 | Paraformer |
| aishell_test_008 | real_aishell | **0.083** | 20.3 | Paraformer |
| conv_zh_001 | real_conversational | **0.160** | 10.6 | Paraformer |
| conv_zh_004 | real_conversational | **0** | 11.2 | Paraformer |
| conv_zh_005 | real_conversational | **0.062** | 9.2 | Paraformer |
| ascend_cs_001 | real_ascend_codeswitching | **0.190** | 2.7 | Paraformer |
| ascend_cs_002 | real_ascend_codeswitching | **0.040** | 5.2 | Paraformer |
| ascend_cs_003 | real_ascend_codeswitching | **0.265** | 9.2 | Paraformer |
| ascend_cs_004 | real_ascend_codeswitching | **0.071** | 14.5 | Paraformer |
| ascend_cs_005 | real_ascend_codeswitching | **0.082** | 2.6 | Paraformer |
| ascend_cs_006 | real_ascend_codeswitching | **0.316** | 2.7 | Paraformer |
| ascend_cs_008 | real_ascend_codeswitching | **0.087** | 7.1 | Paraformer |
| ascend_cs_009 | real_ascend_codeswitching | **0.150** | 10.5 | Paraformer |
| ascend_cs_010 | real_ascend_codeswitching | **0.143** | 4.4 | Paraformer |
| wenet_net_001 | real_wenetspeech | **0.043** | 5.4 | Paraformer |
| wenet_net_002 | real_wenetspeech | **0.154** | 3.1 | Paraformer |
| wenet_net_003 | real_wenetspeech | **0.038** | 5.2 | Paraformer |
| wenet_net_004 | real_wenetspeech | **0.062** | 8.4 | Paraformer |
| wenet_net_005 | real_wenetspeech | **0** | 3.0 | Paraformer |
| wenet_net_006 | real_wenetspeech | **0.220** | 10.0 | Paraformer |
| wenet_net_007 | real_wenetspeech | **0.111** | 4.2 | Paraformer |
| wenet_net_008 | real_wenetspeech | **0.059** | 7.7 | Paraformer |
| wenet_net_009 | real_wenetspeech | **0.189** | 3.6 | Paraformer |
| wenet_net_010 | real_wenetspeech | **0.048** | 7.6 | Paraformer |
| cs_edge_001 | real_codeswitching | **0.097** | 4.1 | Paraformer |
| cs_edge_002 | real_codeswitching | **0.086** | 4.1 | Paraformer |
| cs_edge_003 | real_codeswitching | **0.119** | 3.1 | Paraformer |
| cs_edge_004 | real_codeswitching | **0.068** | 2.9 | Paraformer |
| cs_edge_005 | real_codeswitching | **0.062** | 2.9 | Paraformer |
| cs_edge_006 | real_codeswitching | **0.048** | 4.5 | Paraformer |
| cs_edge_007 | real_codeswitching | **0.091** | 3.1 | Paraformer |
| cs_edge_008 | real_codeswitching | **0.200** | 4.2 | Paraformer |

## 4. 推理速度对比

| Pipeline | 总音频 | 总推理 | RTF | 平均/条 |
|----------|:-----:|:-----:|:---:|:------:|
| Paraformer Pipeline | 421s | 12.8s | 0.030x | 0.19s |
| Paraformer + Qwen3 Rewrite | 421s | 178.2s | 0.423x | 2.66s |

## 5. 各 Pipeline 识别错误案例详细分析

### 5.1 Paraformer Pipeline（41 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | cs_error_01 | 0.379 | 这个error是null pointer exception。 | 这个error是no pointer it se。 | 英文词丢失: null,exception |
| 2 | punct_list_01 | 0.333 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第1步，打开终端。第2步，输入命令。第3步，确认执行。 | 数字/量词 |
| 3 | dev_k8s_01 | 0.324 | Kubernetes的pod状态是CrashLoopBackOff。 | cubonates的pod状态是crash back back。 | 英文词丢失: kubernetes,crashloopbackoff |
| 4 | ascend_cs_006 | 0.316 | 那个玩basketball的，然后我有时候有时候会邀我的friends啊，一起打… | 那个玩玩basketball，然后我就就是稍微邀我的france 1起打在就是a… | 英文词丢失: friends,class, 数字/量词 |
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
| 20 | ascend_cs_010 | 0.143 | 哦，我我在UG的时候念的是electrical engineering。 | 哦，我我在u g的时候念的是electric engineer。 | 英文词丢失: electrical,engineering,ug |
| 21 | pause_long_01 | 0.125 | 我想要一杯咖啡。 | 我想要1杯咖啡。 | 数字/量词 |
| 22 | cs_edge_003 | 0.119 | 用Docker Compose部署了3个microservice到staging… | 用darker compose部署了3个michao service到stagi… | 英文词丢失: docker,microservice, 数字/量词 |
| 23 | wenet_net_007 | 0.111 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺，尽管孤身1人，但与好友见面时还是会爽朗1笑。 | 数字/量词 |
| 24 | aishell_test_004 | 0.105 | 为了规避三四线城市明显过剩的市场风险。 | 为了规避34线城市明显过剩的市场风险。 | 数字/量词 |
| 25 | cs_edge_001 | 0.097 | 我们团队最近在用React和TypeScript重构前端项目。 | 我们团队最近在用react和texcript重构前端项目。 | 英文词丢失: typescript |
| 26 | dev_db_01 | 0.094 | 执行SQL查询SELECT FROM users WHERE id = 1。 | 执行c ql查询select from users where i d于于。 | 英文词丢失: id,sql |
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
| 39 | cs_edge_005 | 0.062 | 这个function的return type应该是Optional，而不是for… | 这个function的return tape应该是optional，而不是for… | 英文词丢失: unwrap,type |
| 40 | wenet_net_008 | 0.059 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来，送到月亮搭上去。 | 同音字/近音字 |
| 41 | long_30s_01 | 0.057 | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解… | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法，使得计算机能够处理和理… | 标点差异 |

### 5.2 Paraformer + Qwen3 Rewrite（67 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | noise_01 | 43.7 | 你好。 | Okay, let's see. The user provided a tex… | 幻觉/冗余 |
| 2 | pause_mid_01 | 40.6 | 打开终端。 | Okay, let's see. The user provided a mix… | 幻觉/冗余 |
| 3 | punct_question_01 | 34.1 | 你今天吃饭了吗？ | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 4 | rate_slow_01 | 31.2 | 慢速语音识别测试。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 5 | zh_short_01 | 29.0 | 今天天气真好。 | Okay, let's see. The user provided a tex… | 幻觉/冗余 |
| 6 | mixed_01 | 22.0 | 我今天用Python写了一个API接口。 | Okay, let's see. The user is asking for … | 英文词丢失: api, 数字/量词, 幻觉/冗余 |
| 7 | aishell_test_006 | 22.0 | 因此，土地储备至关重要。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 8 | aishell_test_008 | 20.3 | 一线城市土地供应量减少。 | Okay, let's see. The user provided a mes… | 数字/量词, 幻觉/冗余 |
| 9 | aishell_test_005 | 18.2 | 标杆房企必然调整市场战略。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 10 | pause_long_01 | 15.5 | 我想要一杯咖啡。 | Okay, let's see. The user is asking for … | 数字/量词, 幻觉/冗余 |
| 11 | aishell_test_002 | 14.6 | 一二线城市虽然也处于调整中。 | Okay, let's see. The user provided a mes… | 数字/量词, 幻觉/冗余 |
| 12 | ascend_cs_004 | 14.5 | 嗯，I like hot pot。 | Okay, let's see. The user is asking for … | 英文词丢失: i,like,pot, 幻觉/冗余 |
| 13 | punct_exclaim_01 | 13.8 | 太好了，我成功了。 | Okay, let's see. The user is asking for … | 幻觉/冗余 |
| 14 | punct_list_01 | 12.8 | 第一步打开终端，第二步输入命令，第三步确认执行。 | Okay, let's see. The user provided a tex… | 数字/量词, 幻觉/冗余 |
| 15 | cs_build_01 | 11.8 | 在macOS上运行swift build。 | Okay, let's see. The user is asking for … | 英文词丢失: macos,build,swift, 幻觉/冗余 |
| 16 | conv_zh_004 | 11.2 | 我想要查询我的账户余额。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 17 | dev_api_01 | 10.7 | 调用RESTful API返回JSON格式数据。 | Okay, let's see. The user wants to know … | 英文词丢失: api,restful,json, 幻觉/冗余 |
| 18 | conv_zh_001 | 10.6 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | Okay, let's see. The user provided a mes… | 数字/量词, 幻觉/冗余 |
| 19 | ascend_cs_009 | 10.5 | 然后刚忘了讲，你你是念什么major的？ | Okay, let's see. The user is asking for … | 英文词丢失: major, 幻觉/冗余 |
| 20 | aishell_test_003 | 10.3 | 但因为聚集了过多公共资源。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 21 | mixed_02 | 10.2 | MacBook Pro M3芯片性能提升了百分之40。 | Okay, let's see. The user is asking for … | 英文词丢失: m,pro,macbook, 数字/量词, 幻觉/冗余 |
| 22 | wenet_net_006 | 10.0 | 这位叫皮特的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官… | Okay, let's see. The user is asking for … | 英文词丢失: fbi, 数字/量词, 幻觉/冗余 |
| 23 | aishell_test_001 | 9.6 | 甚至出现交易几乎停滞的情况。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 24 | aishell_test_007 | 9.6 | 中原地产首席分析师张大伟说。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 25 | ascend_cs_003 | 9.2 | 深圳啊，或者是上海这种比较大的城市，会有更多opportunity。 | Okay, let's see. The user is asking for … | 英文词丢失: opportunity, 幻觉/冗余 |
| 26 | conv_zh_005 | 9.2 | 您好，我可以知道我的账户余额吗？ | Okay, let's see. The user provided a mes… | 幻觉/冗余 |
| 27 | dev_rust_01 | 8.8 | 在Rust里面用async await处理并发。 | Okay, let's see. The user is asking for … | 英文词丢失: await,async,rust, 幻觉/冗余 |
| 28 | dev_url_01 | 8.7 | 访问github.com。 | Okay, let's see. The user provided a mes… | 英文词丢失: github,com, 幻觉/冗余 |
| 29 | tech_num_01 | 8.4 | 服务器IP地址是192.168.1.100，端口号8080。 | Okay, let's see. The user provided some … | 英文词丢失: ip, 数字/量词, 幻觉/冗余 |
| 30 | wenet_net_004 | 8.4 | 下车后望着30多层的大高楼发呆。 | Okay, let's see. The user has provided a… | 数字/量词, 幻觉/冗余 |
| 31 | en_short_01 | 8.3 | Hello world. | Hello, world! How can I assist you today… | 幻觉/冗余 |
| 32 | wenet_net_008 | 7.7 | 把这些劳工抓起来，送到月亮岛上去。 | Okay, let's see. The user provided a tex… | 幻觉/冗余 |
| 33 | dev_git_01 | 7.7 | 执行git commit，修复登录bug。 | Okay, let's see. The user is asking for … | 英文词丢失: bug, 幻觉/冗余 |
| 34 | wenet_net_010 | 7.6 | 媒体也已经报了，然后呃，债主也已经围楼了。 | Okay, let's see. The user provided a mix… | 幻觉/冗余 |
| 35 | dev_swift_01 | 7.3 | 定义一个struct叫做UserModel。 | Okay, let's see. The user provided a mes… | 英文词丢失: usermodel,struct, 数字/量词, 幻觉/冗余 |
| 36 | rate_fast_01 | 7.2 | 快速语音识别测试，1、2、3、4、5。 | Okay, let's see. The user provided a mes… | 数字/量词, 幻觉/冗余 |
| 37 | ascend_cs_008 | 7.1 | 然后呃，我也喜欢play basketball。 | Okay, let's see. The user wants to play … | 英文词丢失: basketball, 幻觉/冗余 |
| 38 | aishell_test_004 | 7.1 | 为了规避三四线城市明显过剩的市场风险。 | Okay, let's see. The user has provided a… | 数字/量词, 幻觉/冗余 |
| 39 | cs_var_01 | 6.3 | 把这个variable赋值给constant。 | Okay, let's see. The user is asking for … | 英文词丢失: variable,constant, 幻觉/冗余 |
| 40 | dev_debug_01 | 6.2 | 在第42行设置一个breakpoint。 | Okay, let's see. The user provided a mes… | 英文词丢失: breakpoint, 数字/量词, 幻觉/冗余 |
| 41 | cs_deploy_01 | 5.7 | 把Docker image push到registry。 | Okay, let's see. The user wants to push … | 英文词丢失: docker, 幻觉/冗余 |
| 42 | wenet_net_001 | 5.4 | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 | Okay, let's see. The user provided a tex… | 幻觉/冗余 |
| 43 | cs_review_01 | 5.4 | 帮我review一下这个pull request。 | Okay, let's see. The user wants me to as… | 英文词丢失: review,pull, 数字/量词, 幻觉/冗余 |
| 44 | ascend_cs_002 | 5.2 | 嗯，所以你现在还是比较focus在找工作这件事上。 | Okay, let's see. The user provided a mes… | 英文词丢失: focus, 幻觉/冗余 |
| 45 | wenet_net_003 | 5.2 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 46 | cs_edge_006 | 4.5 | 用Xcode的Instruments做了一下profiling，发现CPU占用太… | Okay, let's see. The user is asking for … | 英文词丢失: instruments,xcode,profiling, 数字/量词, 幻觉/冗余 |
| 47 | dev_db_01 | 4.5 | 执行SQL查询SELECT FROM users WHERE id = 1。 | Okay, let's see. The user is asking to s… | 英文词丢失: id,sql, 数字/量词, 幻觉/冗余 |
| 48 | ascend_cs_010 | 4.4 | 哦，我我在UG的时候念的是electrical engineering。 | Okay, let's see. The user is asking for … | 英文词丢失: electrical,engineering,ug, 幻觉/冗余 |
| 49 | cs_error_01 | 4.3 | 这个error是null pointer exception。 | Okay, let's see. The user is having a pr… | 英文词丢失: pointer,exception,null, 幻觉/冗余 |
| 50 | wenet_net_007 | 4.2 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | Okay, let's see. The user provided a mix… | 数字/量词, 幻觉/冗余 |
| 51 | cs_edge_008 | 4.2 | CI pipeline跑了30分钟，还没通过unit test。 | Okay, let's see. The user is asking for … | 英文词丢失: pipeline,ci,unit, 数字/量词, 幻觉/冗余 |
| 52 | cs_edge_001 | 4.1 | 我们团队最近在用React和TypeScript重构前端项目。 | Okay, let's see. The user provided a tex… | 英文词丢失: typescript,react, 幻觉/冗余 |
| 53 | cs_edge_002 | 4.1 | 这个bug是因为race condition导致的memory leak。 | Okay, let's see. The user is asking abou… | 英文词丢失: leak,race, 幻觉/冗余 |
| 54 | zh_long_01 | 3.9 | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析… | Okay, let's see. The user provided a mix… | 幻觉/冗余 |
| 55 | wenet_net_009 | 3.6 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | Okay, let's see. The user has provided a… | 幻觉/冗余 |
| 56 | cs_edge_003 | 3.1 | 用Docker Compose部署了3个microservice到staging… | Okay, let's see. The user is asking for … | 英文词丢失: staging,compose,docker, 数字/量词, 幻觉/冗余 |
| 57 | cs_edge_007 | 3.1 | GraphQL的schema定义比RESTful API更灵活一些。 | Okay, let's see. The user wants a graph,… | 英文词丢失: graphql,api,restful, 数字/量词, 幻觉/冗余 |
| 58 | dev_k8s_01 | 3.1 | Kubernetes的pod状态是CrashLoopBackOff。 | Okay, let's see. The user is asking for … | 英文词丢失: pod,kubernetes,crashloopbackoff, 幻觉/冗余 |
| 59 | wenet_net_002 | 3.1 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有… | Okay, let's see. The user provided a mix… | 幻觉/冗余 |
| 60 | wenet_net_005 | 3.0 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构… | Okay, let's see. The user provided a tex… | 幻觉/冗余 |
| 61 | cs_edge_004 | 2.9 | 在GitHub上提了一个issue，关于performance optimiza… | Okay, let's see. The user is asking for … | 英文词丢失: performance,issue, 数字/量词, 幻觉/冗余 |
| 62 | cs_edge_005 | 2.9 | 这个function的return type应该是Optional，而不是for… | Okay, let's see. The user is asking for … | 英文词丢失: return,type,unwrap, 幻觉/冗余 |
| 63 | long_60s_01 | 2.9 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及… | 1. 1. 1. 1. 1. 1. 1. 1. 1. 1. 1. 1. 1. 1… | 英文词丢失: git,docker,devops, 数字/量词, 幻觉/冗余 |
| 64 | ascend_cs_001 | 2.7 | No，我专业是那个ISM，Information Systems Managem… | 好的，用户发来了一段关于“信息系统管理”的信息，看起来他们可能在学习或工作，需要… | 英文词丢失: management,ism,information, 幻觉/冗余 |
| 65 | ascend_cs_006 | 2.7 | 那个玩basketball的，然后我有时候有时候会邀我的friends啊，一起打… | Okay, let's see. The user is asking for … | 英文词丢失: friends,class,basketball, 数字/量词, 幻觉/冗余 |
| 66 | ascend_cs_005 | 2.6 | 所以我的我的parents，我的妈妈是chemistry老师，and我的爸爸是h… | Okay, let's see. The user is asking for … | 英文词丢失: parents, 幻觉/冗余 |
| 67 | long_30s_01 | 1.000 | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解… | Okay, let's see. The user provided a mix… | 数字/量词 |

## 6. 综合分析与建议

### 各场景最佳 Pipeline 推荐

| 场景 | 推荐 Pipeline | CER |
|------|--------------|:---:|
| chinese_long | Paraformer Pipeline | 0.024 |
| chinese_short | Paraformer Pipeline | 0.000 |
| code_switching | Paraformer Pipeline | 0.144 |
| developer_corpus | Paraformer Pipeline | 0.135 |
| english_short | Paraformer Pipeline | 0.091 |
| long_audio | Paraformer Pipeline | 0.066 |
| mid_sentence_pause | Paraformer Pipeline | 0.062 |
| mixed_technical | Paraformer Pipeline | 0.000 |
| mixed_zh_en | Paraformer Pipeline | 0.050 |
| punctuation | Paraformer Pipeline | 0.111 |
| real_aishell | Paraformer Pipeline | 0.051 |
| real_ascend_codeswitching | Paraformer Pipeline | 0.149 |
| real_codeswitching | Paraformer Pipeline | 0.096 |
| real_conversational | Paraformer Pipeline | 0.074 |
| real_wenetspeech | Paraformer Pipeline | 0.092 |
| speech_rate | Paraformer Pipeline | 0.132 |
| speech_trailing_silence | Paraformer Pipeline | 0.000 |
| technical_numbers | Paraformer Pipeline | 0.267 |

### Pipeline 特点总结

**Paraformer Pipeline**
- 平均 CER: 0.1008
- 完美识别 (CER=0): 15/67 条
- 不准确 (CER>5%): 41/67 条
- RTF: 0.030x

**Paraformer + Qwen3 Rewrite**
- 平均 CER: 9.9043
- 完美识别 (CER=0): 0/67 条
- 不准确 (CER>5%): 67/67 条
- RTF: 0.423x

---

*报告由 `scripts/benchmark_engines.py` 自动生成*