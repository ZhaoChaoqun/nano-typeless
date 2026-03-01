# ASR 引擎量化对比评估报告

*生成时间：2026-03-01 18:29*
*测试集：70 条音频（corpus.json + real_manifest.json）*
*引擎：Qwen3-ASR (离线), Qwen3-ASR (流式), Streaming Paraformer, SenseVoice Nano*

---

## 1. 总体 CER 汇总

| 引擎 | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Qwen3-ASR (离线) | 0.0472 | 46/70 | 60 | 66 | 4 | 39.9s | 0.092x |
| Qwen3-ASR (流式) | 0.0829 | 41/70 | 55 | 63 | 7 | 86.9s | 0.200x |
| Streaming Paraformer | 0.1128 | 16/70 | 41 | 58 | 12 | 12.5s | 0.029x |
| SenseVoice Nano | 0.0827 | 25/70 | 50 | 62 | 8 | 9.6s | 0.022x |

## 2. 按数据集/类别的平均 CER

| 类别 | N | Qwen3-ASR | Qwen3-ASR | Streaming Pa | SenseVoice N | 最佳引擎 |
|------|:-:|:------:|:------:|:------:|:------:|---------|
| chinese_long | 1 | **0.000** | 0.000 | 0.026 | 0.026 | Qwen3-ASR |
| chinese_short | 1 | **0.000** | 0.000 | 0.000 | 0.000 | Qwen3-ASR |
| code_switching | 5 | **0.018** | 0.018 | 0.150 | 0.055 | Qwen3-ASR |
| developer_corpus | 8 | **0.070** | 0.070 | 0.163 | 0.147 | Qwen3-ASR |
| english_short | 1 | **0.000** | 0.000 | 0.000 | 0.000 | Qwen3-ASR |
| long_audio | 2 | **0.000** | 0.758 | 0.028 | 0.007 | Qwen3-ASR |
| mid_sentence_pause | 2 | **0.000** | 0.000 | 0.071 | 0.000 | Qwen3-ASR |
| mixed_technical | 1 | **0.042** | 0.042 | 0.083 | 0.042 | Qwen3-ASR |
| mixed_zh_en | 1 | **0.000** | 0.000 | 0.053 | 0.053 | Qwen3-ASR |
| punctuation | 3 | **0.000** | 0.000 | 0.048 | 0.000 | Qwen3-ASR |
| real_aishell | 8 | **0.000** | 0.094 | 0.055 | 0.017 | Qwen3-ASR |
| real_ascend_codeswitching | 10 | **0.093** | 0.098 | 0.180 | 0.131 | Qwen3-ASR |
| real_codeswitching | 8 | **0.000** | 0.013 | 0.108 | 0.120 | Qwen3-ASR |
| real_conversational | 5 | 0.206 | 0.224 | 0.111 | **0.068** | SenseVoice Nano |
| real_wenetspeech | 10 | 0.057 | **0.056** | 0.101 | 0.066 | Qwen3-ASR |
| speech_rate | 2 | **0.000** | 0.000 | 0.192 | 0.038 | Qwen3-ASR |
| speech_trailing_silence | 1 | **0.000** | 0.000 | 0.000 | 0.000 | Qwen3-ASR |
| technical_numbers | 1 | **0.080** | 0.080 | 0.280 | 0.720 | Qwen3-ASR |
| **OVERALL** | 70 | **0.0472** | 0.0829 | 0.1128 | 0.0827 | **Qwen3-ASR** |

## 3. 逐条 CER 对比

| ID | 类别 | Q(离线) | Q(流式) | S.Paraform | SV Nano | 最佳 |
|-----|------|:-----:|:-----:|:-----:|:-----:|------|
| zh_short_01 | chinese_short | **0** | **0** | **0** | **0** | Qwen3-AS |
| zh_long_01 | chinese_long | **0** | **0** | 0.026 | 0.026 | Qwen3-AS |
| mixed_01 | mixed_zh_en | **0** | **0** | 0.053 | 0.053 | Qwen3-AS |
| mixed_02 | mixed_technical | **0.042** | 0.042 | 0.083 | 0.042 | Qwen3-AS |
| en_short_01 | english_short | **0** | **0** | **0** | **0** | Qwen3-AS |
| tech_num_01 | technical_numbers | **0.080** | 0.080 | 0.280 | 0.720 | Qwen3-AS |
| noise_01 | speech_trailing_silence | **0** | **0** | **0** | **0** | Qwen3-AS |
| dev_git_01 | developer_corpus | **0** | **0** | 0.056 | **0** | Qwen3-AS |
| dev_swift_01 | developer_corpus | **0.048** | 0.048 | 0.048 | 0.333 | Qwen3-AS |
| dev_rust_01 | developer_corpus | **0** | **0** | 0.227 | 0.136 | Qwen3-AS |
| dev_k8s_01 | developer_corpus | **0** | **0** | 0.333 | 0.121 | Qwen3-AS |
| dev_api_01 | developer_corpus | **0** | **0** | 0.045 | 0.136 | Qwen3-AS |
| dev_db_01 | developer_corpus | 0.094 | 0.094 | **0.062** | 0.062 | Streamin |
| dev_url_01 | developer_corpus | 0.417 | 0.417 | **0.333** | 0.333 | Streamin |
| dev_debug_01 | developer_corpus | **0** | **0** | 0.200 | 0.050 | Qwen3-AS |
| cs_var_01 | code_switching | 0.091 | 0.091 | **0** | **0** | Streamin |
| cs_build_01 | code_switching | **0** | **0** | 0.316 | **0** | Qwen3-AS |
| cs_error_01 | code_switching | **0** | **0** | 0.393 | 0.107 | Qwen3-AS |
| cs_deploy_01 | code_switching | **0** | **0** | **0** | 0.080 | Qwen3-AS |
| cs_review_01 | code_switching | **0** | **0** | 0.043 | 0.087 | Qwen3-AS |
| punct_question_01 | punctuation | **0** | **0** | **0** | **0** | Qwen3-AS |
| punct_exclaim_01 | punctuation | **0** | **0** | **0** | **0** | Qwen3-AS |
| punct_list_01 | punctuation | **0** | **0** | 0.143 | **0** | Qwen3-AS |
| rate_fast_01 | speech_rate | **0** | **0** | 0.385 | 0.077 | Qwen3-AS |
| rate_slow_01 | speech_rate | **0** | **0** | **0** | **0** | Qwen3-AS |
| long_30s_01 | long_audio | **0** | 0.676 | 0.027 | 0.005 | Qwen3-AS |
| long_60s_01 | long_audio | **0** | 0.840 | 0.028 | 0.009 | Qwen3-AS |
| pause_mid_01 | mid_sentence_pause | **0** | **0** | **0** | **0** | Qwen3-AS |
| pause_long_01 | mid_sentence_pause | **0** | **0** | 0.143 | **0** | Qwen3-AS |
| aishell_test_001 | real_aishell | **0** | **0** | **0** | **0** | Qwen3-AS |
| aishell_test_002 | real_aishell | **0** | **0** | 0.154 | **0** | Qwen3-AS |
| aishell_test_003 | real_aishell | **0** | 0.750 | **0** | 0.083 | Qwen3-AS |
| aishell_test_004 | real_aishell | **0** | **0** | 0.111 | 0.056 | Qwen3-AS |
| aishell_test_005 | real_aishell | **0** | **0** | 0.083 | **0** | Qwen3-AS |
| aishell_test_006 | real_aishell | **0** | **0** | **0** | **0** | Qwen3-AS |
| aishell_test_007 | real_aishell | **0** | **0** | **0** | **0** | Qwen3-AS |
| aishell_test_008 | real_aishell | **0** | **0** | 0.091 | **0** | Qwen3-AS |
| conv_zh_001 | real_conversational | **0.045** | 0.136 | 0.136 | 0.091 | Qwen3-AS |
| conv_zh_002 | real_conversational | 0.417 | 0.417 | 0.250 | **0** | SenseVoi |
| conv_zh_003 | real_conversational | 0.400 | 0.400 | **0** | **0** | Streamin |
| conv_zh_004 | real_conversational | **0** | **0** | **0** | **0** | Qwen3-AS |
| conv_zh_005 | real_conversational | **0.167** | 0.167 | 0.167 | 0.250 | Qwen3-AS |
| ascend_cs_001 | real_ascend_codeswitching | **0.051** | 0.103 | 0.154 | 0.128 | Qwen3-AS |
| ascend_cs_002 | real_ascend_codeswitching | **0.043** | 0.043 | 0.130 | 0.130 | Qwen3-AS |
| ascend_cs_003 | real_ascend_codeswitching | 0.355 | 0.355 | 0.516 | **0.323** | SenseVoi |
| ascend_cs_004 | real_ascend_codeswitching | **0.083** | 0.083 | 0.083 | 0.083 | Qwen3-AS |
| ascend_cs_005 | real_ascend_codeswitching | **0.065** | 0.065 | 0.087 | 0.109 | Qwen3-AS |
| ascend_cs_006 | real_ascend_codeswitching | **0.111** | 0.111 | 0.315 | 0.167 | Qwen3-AS |
| ascend_cs_007 | real_ascend_codeswitching | **0** | **0** | 0.118 | 0.059 | Qwen3-AS |
| ascend_cs_008 | real_ascend_codeswitching | 0.048 | 0.048 | 0.190 | **0** | SenseVoi |
| ascend_cs_009 | real_ascend_codeswitching | **0.111** | 0.111 | 0.111 | 0.278 | Qwen3-AS |
| ascend_cs_010 | real_ascend_codeswitching | 0.065 | 0.065 | 0.097 | **0.032** | SenseVoi |
| wenet_net_001 | real_wenetspeech | **0** | **0** | 0.050 | **0** | Qwen3-AS |
| wenet_net_002 | real_wenetspeech | **0.128** | 0.170 | 0.149 | 0.149 | Qwen3-AS |
| wenet_net_003 | real_wenetspeech | **0** | **0** | **0** | **0** | Qwen3-AS |
| wenet_net_004 | real_wenetspeech | **0** | **0** | 0.133 | **0** | Qwen3-AS |
| wenet_net_005 | real_wenetspeech | **0** | **0** | 0.025 | 0.050 | Qwen3-AS |
| wenet_net_006 | real_wenetspeech | 0.128 | 0.128 | 0.231 | **0.077** | SenseVoi |
| wenet_net_007 | real_wenetspeech | **0.061** | 0.061 | 0.152 | 0.061 | Qwen3-AS |
| wenet_net_008 | real_wenetspeech | **0** | **0** | 0.067 | 0.067 | Qwen3-AS |
| wenet_net_009 | real_wenetspeech | **0.091** | 0.091 | 0.152 | 0.091 | Qwen3-AS |
| wenet_net_010 | real_wenetspeech | 0.167 | 0.111 | **0.056** | 0.167 | Streamin |
| cs_edge_001 | real_codeswitching | **0** | **0** | 0.100 | 0.233 | Qwen3-AS |
| cs_edge_002 | real_codeswitching | **0** | **0** | 0.088 | 0.088 | Qwen3-AS |
| cs_edge_003 | real_codeswitching | **0** | **0** | 0.146 | 0.098 | Qwen3-AS |
| cs_edge_004 | real_codeswitching | **0** | **0** | 0.071 | 0.214 | Qwen3-AS |
| cs_edge_005 | real_codeswitching | **0** | **0** | 0.065 | 0.065 | Qwen3-AS |
| cs_edge_006 | real_codeswitching | **0** | **0** | 0.050 | 0.125 | Qwen3-AS |
| cs_edge_007 | real_codeswitching | **0** | 0.031 | 0.094 | 0.031 | Qwen3-AS |
| cs_edge_008 | real_codeswitching | **0** | 0.071 | 0.250 | 0.107 | Qwen3-AS |

## 4. 推理速度对比

| 引擎 | 总音频 | 总推理 | RTF | 平均/条 |
|------|:-----:|:-----:|:---:|:------:|
| Qwen3-ASR (离线) | 434s | 39.9s | 0.092x | 0.57s |
| Qwen3-ASR (流式) | 434s | 86.9s | 0.200x | 1.24s |
| Streaming Paraformer | 434s | 12.5s | 0.029x | 0.18s |
| SenseVoice Nano | 434s | 9.6s | 0.022x | 0.14s |

## 5. 各引擎识别错误案例详细分析

### 5.1 Qwen3-ASR (离线)（19 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | dev_url_01 | 0.417 | 访问github点com | 访问 GuessUp 点 com。 | 英文词丢失: github |
| 2 | conv_zh_002 | 0.417 | 我想查询我目前的账户余额 | 我想查詢我目前的帳戶餘額。 | 综合误差 |
| 3 | conv_zh_003 | 0.400 | 我的账户还有多少钱呢 | 我的賬戶還有多少錢呢？ | 综合误差 |
| 4 | ascend_cs_003 | 0.355 | 深圳啊或者是上海这种比较大的城市会有更多opportunity | 深圳啊，或者是上海这种比较大的城市，会有更多不听。 | 英文词丢失: opportunity |
| 5 | conv_zh_005 | 0.167 | 我可以知道我的账户余额吗 | 您好，我可以知道我的账户余额吗？ | 同音字/近音字 |
| 6 | wenet_net_010 | 0.167 | 媒体也已经报了然后呃债主也已经围楼了 | 媒体也已经爆了，然后呃，在座也已经围楼了。 | 同音字/近音字 |
| 7 | wenet_net_006 | 0.128 | 这位叫皮特的FBI探员一上来就一顿物理分析认为阿曼达不可能吊起比她还重的女警官 | 这位叫Peter的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的… | 数字/量词 |
| 8 | wenet_net_002 | 0.128 | 竖锯癌症病成那样还打着点滴就更不可能把女警官吊了起来说来说去皮特认为还有其他人在… | 数据癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，彼得认为还有… | 同音字/近音字 |
| 9 | ascend_cs_006 | 0.111 | 那个玩basketball的然后我有时候有时候会邀我的friends啊一起打在就… | 那个玩basketball的，然后我就说：“我会邀我的friends啊，一起打在… | 数字/量词 |
| 10 | ascend_cs_009 | 0.111 | 然后刚忘了讲你你是念什么major的 | 然后刚刚忘了讲你你是念什么major了。 | 同音字/近音字 |
| 11 | dev_db_01 | 0.094 | 执行SQL查询SELECT FROM users WHERE id等于一 | 执行 SQL 查询：SELECT FROM users WHERE id = 1… | 同音字/近音字 |
| 12 | cs_var_01 | 0.091 | 把这个variable赋值给constant | 把这个 variable 复制给 constant。 | 同音字/近音字 |
| 13 | wenet_net_009 | 0.091 | 的的需要嗯如果你把他当成产品的话你就会觉得那么消费者会需要什么样的 | 的的需要。如果你把它当成产品的话，你会觉得那么消费者会需要什么样的。 | 同音字/近音字 |
| 14 | ascend_cs_004 | 0.083 | 嗯I like hot pot | 嗯，我，like hot pot。 | 英文词丢失: i |
| 15 | tech_num_01 | 0.080 | 服务器IP地址是192.168.1.100端口号8080 | 服务器 IP 地址是 192.168.1.100，端口号 8008。 | 同音字/近音字 |
| 16 | ascend_cs_005 | 0.065 | 所以我的我的parents我的妈妈是chemistry老师and我的爸爸是his… | 所以我的我的parents，我的妈妈是chemistry老师，然后我的爸爸是hi… | 英文词丢失: and |
| 17 | ascend_cs_010 | 0.065 | 哦我我在u g的时候念的是electric engineering | 哦，我我在UG的时候念的是Electrical Engineering。 | 英文词丢失: u,g,electric |
| 18 | wenet_net_007 | 0.061 | 她已经在商场里开起了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 | 他已经在商场里开启了小店铺。尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 同音字/近音字 |
| 19 | ascend_cs_001 | 0.051 | no我专业是那个i s m information systems manage… | 那我专业是那个ISM Information Systems Managemen… | 英文词丢失: i,m,no |

### 5.2 Qwen3-ASR (流式)（24 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | long_60s_01 | 0.840 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及… | 软件工程是一门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。它涉… | 英文词丢失: git,devops,docker, 数字/量词, 截断 |
| 2 | aishell_test_003 | 0.750 | 但因为聚集了过多公共资源 | 但因为 | 截断 |
| 3 | long_30s_01 | 0.676 | 人工智能技术在过去十年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解自… | 人工智能技术在过去十年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解自… | 数字/量词, 截断 |
| 4 | dev_url_01 | 0.417 | 访问github点com | 访问 GuessUp 点 com。 | 英文词丢失: github |
| 5 | conv_zh_002 | 0.417 | 我想查询我目前的账户余额 | 我想查詢我目前的帳戶餘額。 | 综合误差 |
| 6 | conv_zh_003 | 0.400 | 我的账户还有多少钱呢 | 我的賬戶還有多少錢呢？ | 综合误差 |
| 7 | ascend_cs_003 | 0.355 | 深圳啊或者是上海这种比较大的城市会有更多opportunity | 深圳啊，或者是上海这种比较大的城市，会有更多不听。 | 英文词丢失: opportunity |
| 8 | wenet_net_002 | 0.170 | 竖锯癌症病成那样还打着点滴就更不可能把女警官吊了起来说来说去皮特认为还有其他人在… | 数据：癌症病成那样，还点滴，就更不可能把女警官吊了起来。说来说去，彼得认为还有其… | 同音字/近音字 |
| 9 | conv_zh_005 | 0.167 | 我可以知道我的账户余额吗 | 您好，我可以知道我的账户余额吗？ | 同音字/近音字 |
| 10 | conv_zh_001 | 0.136 | 你好我想要了解一下我的银行账户余额有多少谢谢 | 你好，我想要了解一下我的银行账户的有多少。呃，谢谢。 | 数字/量词 |
| 11 | wenet_net_006 | 0.128 | 这位叫皮特的FBI探员一上来就一顿物理分析认为阿曼达不可能吊起比她还重的女警官 | 这位叫Peter的FBI探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的… | 数字/量词 |
| 12 | ascend_cs_006 | 0.111 | 那个玩basketball的然后我有时候有时候会邀我的friends啊一起打在就… | 那个玩basketball的，然后我就说：“我会邀我的friends啊，一起打在… | 数字/量词 |
| 13 | ascend_cs_009 | 0.111 | 然后刚忘了讲你你是念什么major的 | 然后刚刚忘了讲你你是念什么major了。 | 同音字/近音字 |
| 14 | wenet_net_010 | 0.111 | 媒体也已经报了然后呃债主也已经围楼了 | 媒体也已经报了，然后呃，在座也已经围楼了。 | 同音字/近音字 |
| 15 | ascend_cs_001 | 0.103 | no我专业是那个i s m information systems manage… | 那我最爱是那个ISM Information Systems Managemen… | 英文词丢失: i,m,no |
| 16 | dev_db_01 | 0.094 | 执行SQL查询SELECT FROM users WHERE id等于一 | 执行 SQL 查询：SELECT FROM users WHERE id = 1… | 同音字/近音字 |
| 17 | cs_var_01 | 0.091 | 把这个variable赋值给constant | 把这个 variable 复制给 constant。 | 同音字/近音字 |
| 18 | wenet_net_009 | 0.091 | 的的需要嗯如果你把他当成产品的话你就会觉得那么消费者会需要什么样的 | 的的需要。如果你把它当成产品的话，你会觉得那么消费者会需要什么样的。 | 同音字/近音字 |
| 19 | ascend_cs_004 | 0.083 | 嗯I like hot pot | 嗯，我，like hot pot。 | 英文词丢失: i |
| 20 | tech_num_01 | 0.080 | 服务器IP地址是192.168.1.100端口号8080 | 服务器 IP 地址是 192.168.1.100，端口号 8008。 | 同音字/近音字 |
| 21 | cs_edge_008 | 0.071 | CI pipeline跑了三十分钟还没通过unit test | C I pipeline跑了分钟，还没通过unit test。 | 英文词丢失: ci |
| 22 | ascend_cs_005 | 0.065 | 所以我的我的parents我的妈妈是chemistry老师and我的爸爸是his… | 所以我的我的parents我的妈妈是chemistry老师，，然后我的爸爸是hi… | 英文词丢失: and |
| 23 | ascend_cs_010 | 0.065 | 哦我我在u g的时候念的是electric engineering | 哦，我我在UG的时候念的是Electrical Engineering。 | 英文词丢失: u,g,electric |
| 24 | wenet_net_007 | 0.061 | 她已经在商场里开起了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 | 他已经在商场里开启了小店铺。尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 同音字/近音字 |

### 5.3 Streaming Paraformer（45 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | ascend_cs_003 | 0.516 | 深圳啊或者是上海这种比较大的城市会有更多opportunity | 深圳啊或者是上海这种表达城市会有更 | 英文词丢失: opportunity, 截断 |
| 2 | cs_error_01 | 0.393 | 这个error是null pointer exception | 这个error是no pointer it se | 英文词丢失: exception,null |
| 3 | rate_fast_01 | 0.385 | 快速语音识别测试一二三四五 | 快速语音识别测试12345 | 数字/量词 |
| 4 | dev_k8s_01 | 0.333 | Kubernetes的pod状态是CrashLoopBackOff | cubonates的pod状态是crash back back | 英文词丢失: kubernetes,crashloopbackoff |
| 5 | dev_url_01 | 0.333 | 访问github点com | 访问gesub点co | 英文词丢失: github,com |
| 6 | cs_build_01 | 0.316 | 在macOS上运行swift build | 在michael s上运行swift buil | 英文词丢失: macos,build |
| 7 | ascend_cs_006 | 0.315 | 那个玩basketball的然后我有时候有时候会邀我的friends啊一起打在就… | 那个玩玩basketball然后我就就是稍微邀我的france 1起打在就是af… | 英文词丢失: class,friends, 数字/量词 |
| 8 | tech_num_01 | 0.280 | 服务器IP地址是192.168.1.100端口号8080 | 服务器ip地址是幺92点幺68点幺点幺00端口号8080 | 数字/量词 |
| 9 | conv_zh_002 | 0.250 | 我想查询我目前的账户余额 | 那么想查询我目前的账户余 | 同音字/近音字 |
| 10 | cs_edge_008 | 0.250 | CI pipeline跑了三十分钟还没通过unit test | cii pipeline跑了30分钟还没通过unit | 英文词丢失: test,ci, 数字/量词 |
| 11 | wenet_net_006 | 0.231 | 这位叫皮特的FBI探员一上来就一顿物理分析认为阿曼达不可能吊起比她还重的女警官 | 这位叫peter的f b i探员1上来就1顿物理分析认为阿曼达不可能吊起比他还重… | 英文词丢失: fbi, 数字/量词 |
| 12 | dev_rust_01 | 0.227 | 在Rust里面用async await处理并发 | 在rust里面用a think wait处理并发 | 英文词丢失: await,async |
| 13 | dev_debug_01 | 0.200 | 在第四十二行设置一个breakpoint | 在第42行设置1个break point | 英文词丢失: breakpoint, 数字/量词 |
| 14 | ascend_cs_008 | 0.190 | 然后呃我也喜欢play basketball | 然后呃我也喜play basketb | 英文词丢失: basketball |
| 15 | conv_zh_005 | 0.167 | 我可以知道我的账户余额吗 | 民好我可以知道我的账户余额吗 | 同音字/近音字 |
| 16 | aishell_test_002 | 0.154 | 一二线城市虽然也处于调整中 | 12线城市虽然也处于调整中 | 数字/量词 |
| 17 | ascend_cs_001 | 0.154 | no我专业是那个i s m information systems manage… | 那我就暗示那个i s n information systems managem… | 英文词丢失: m,no |
| 18 | wenet_net_007 | 0.152 | 她已经在商场里开起了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 | 他已经在商场里开启了小店铺尽管孤身1人但与好友见面时还是会爽朗1 | 数字/量词 |
| 19 | wenet_net_009 | 0.152 | 的的需要嗯如果你把他当成产品的话你就会觉得那么消费者会需要什么样的 | 的的的需要啊如果你把它当成产品的话你会会觉得那么消费者会需要什么样 | 同音字/近音字 |
| 20 | wenet_net_002 | 0.149 | 竖锯癌症病成那样还打着点滴就更不可能把女警官吊了起来说来说去皮特认为还有其他人在… | 数据癌症病成那样还打着点滴就更不可能把女主官吊了起来说来说去彼得认为还有其他人在… | 同音字/近音字 |
| 21 | cs_edge_003 | 0.146 | 用Docker Compose部署了三个microservice到staging… | 用darker compose部署了3个michao service到stagi… | 英文词丢失: microservice,docker, 数字/量词 |
| 22 | punct_list_01 | 0.143 | 第一步打开终端，第二步输入命令，第三步确认执行 | 第1步打开终端第2步输入命令第3步确认执行 | 数字/量词 |
| 23 | pause_long_01 | 0.143 | 我想要一杯咖啡 | 我想要1杯咖啡 | 数字/量词 |
| 24 | conv_zh_001 | 0.136 | 你好我想要了解一下我的银行账户余额有多少谢谢 | 你好我想要了解1下我的银行账户的余额有多少呃谢谢 | 数字/量词 |
| 25 | wenet_net_004 | 0.133 | 下车后望着三十多层的大高楼发呆 | 下车后望着30多层的大高楼发呆 | 数字/量词 |
| 26 | ascend_cs_002 | 0.130 | 嗯所以你现在还是比较focus在找工作这件事上 | 嗯所以你现在还是比较focus在找工作这 | 同音字/近音字 |
| 27 | ascend_cs_007 | 0.118 | 对我平时然后都喜欢跟Tony一起玩 | 对我平时然后都喜欢跟tony 1起 | 数字/量词 |
| 28 | aishell_test_004 | 0.111 | 为了规避三四线城市明显过剩的市场风险 | 为了规避34线城市明显过剩的市场风险 | 数字/量词 |
| 29 | ascend_cs_009 | 0.111 | 然后刚忘了讲你你是念什么major的 | 然后刚忘了讲1你是念什么major | 同音字/近音字 |
| 30 | cs_edge_001 | 0.100 | 我们团队最近在用React和TypeScript重构前端项目 | 我们团队最近在用react和texcript重构前端项目 | 英文词丢失: typescript |
| 31 | ascend_cs_010 | 0.097 | 哦我我在u g的时候念的是electric engineering | 哦我我在u g的时候念的是electric engineer | 英文词丢失: engineering |
| 32 | cs_edge_007 | 0.094 | GraphQL的schema定义比RESTful API更灵活一些 | graph q l的schema定义笔restful api更灵活1 | 英文词丢失: graphql |
| 33 | aishell_test_008 | 0.091 | 一线城市土地供应量减少 | 1线城市土地供应量减少 | 同音字/近音字 |
| 34 | cs_edge_002 | 0.088 | 这个bug是因为race condition导致的memory leak | 这个bug是因为race condition导致的memory li | 英文词丢失: leak |
| 35 | ascend_cs_005 | 0.087 | 所以我的我的parents我的妈妈是chemistry老师and我的爸爸是his… | 所以我的我的parents我的妈妈是chemistry老师嗯我的爸爸是histo… | 英文词丢失: and |
| 36 | mixed_02 | 0.083 | MacBook Pro M3芯片性能提升了百分之四十 | macbook pro m 3芯片性能提升了百分之40 | 同音字/近音字 |
| 37 | aishell_test_005 | 0.083 | 标杆房企必然调整市场战略 | 标杆房企必然调整市场占略 | 同音字/近音字 |
| 38 | ascend_cs_004 | 0.083 | 嗯I like hot pot | 嗯i d like hot pot | 同音字/近音字 |
| 39 | cs_edge_004 | 0.071 | 在GitHub上提了一个issue关于performance optimizat… | 在github上提了1个约sue关于performance optimizati… | 英文词丢失: issue |
| 40 | wenet_net_008 | 0.067 | 把这些劳工抓起来送到月亮岛上去 | 把这些劳工抓起来送到月亮搭上去 | 同音字/近音字 |
| 41 | cs_edge_005 | 0.065 | 这个function的return type应该是Optional而不是forc… | 这个function的return tape应该是optional而不是forc… | 英文词丢失: type,unwrap |
| 42 | dev_db_01 | 0.062 | 执行SQL查询SELECT FROM users WHERE id等于一 | 执行c ql查询select from users where i d等于 | 英文词丢失: id,sql |
| 43 | dev_git_01 | 0.056 | 执行git commit修复登录bug | 执行git commit修复登录bu | 英文词丢失: bug |
| 44 | wenet_net_010 | 0.056 | 媒体也已经报了然后呃债主也已经围楼了 | 媒体也已经报了然后呃债主也已经为楼了 | 同音字/近音字 |
| 45 | mixed_01 | 0.053 | 我今天用Python写了一个API接口 | 我今天用python写了1个api接口 | 同音字/近音字 |

### 5.4 SenseVoice Nano（37 条不准确）

| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |
|:-:|-----|:---:|---------|---------|---------|
| 1 | tech_num_01 | 0.720 | 服务器IP地址是192.168.1.100端口号8080 | 服务器ip地址是幺九二点幺六八点幺点幺零零端口号八千零八十 | 数字/量词 |
| 2 | dev_swift_01 | 0.333 | 定义一个struct叫做UserModel | 定义一个strap叫做model | 英文词丢失: usermodel,struct, 数字/量词 |
| 3 | dev_url_01 | 0.333 | 访问github点com | 访问g up点com | 英文词丢失: github |
| 4 | ascend_cs_003 | 0.323 | 深圳啊或者是上海这种比较大的城市会有更多opportunity | 深圳啊或者是上海这种比大城市会有更多pot径 | 英文词丢失: opportunity |
| 5 | ascend_cs_009 | 0.278 | 然后刚忘了讲你你是念什么major的 | 然后刚刚忘了讲你你是练什么majorjor的 | 英文词丢失: major |
| 6 | conv_zh_005 | 0.250 | 我可以知道我的账户余额吗 | 您好我可以知道我的账库余额吗 | 同音字/近音字 |
| 7 | cs_edge_001 | 0.233 | 我们团队最近在用React和TypeScript重构前端项目 | 我们团队最近在用act和actcript重构前端项目 | 英文词丢失: react,typescript |
| 8 | cs_edge_004 | 0.214 | 在GitHub上提了一个issue关于performance optimizat… | 在g上提了一个yes关于performance optimization | 英文词丢失: github,issue, 数字/量词 |
| 9 | ascend_cs_006 | 0.167 | 那个玩basketball的然后我有时候有时候会邀我的friends啊一起打在就… | 那个玩basketball然后我就说稍会邀我的friends啊一起打在就是aft… | 英文词丢失: class,after, 数字/量词 |
| 10 | wenet_net_010 | 0.167 | 媒体也已经报了然后呃债主也已经围楼了 | 媒体也已经爆了然后呃在族也已经围楼了 | 同音字/近音字 |
| 11 | wenet_net_002 | 0.149 | 竖锯癌症病成那样还打着点滴就更不可能把女警官吊了起来说来说去皮特认为还有其他人在… | 数据癌症病成那样还打着点滴就更不可能把女警官吊了起来说来说去比德认为还有其他人在… | 同音字/近音字 |
| 12 | dev_rust_01 | 0.136 | 在Rust里面用async await处理并发 | 在rust里面用ync wait处理并发 | 英文词丢失: await,async |
| 13 | dev_api_01 | 0.136 | 调用RESTful API返回JSON格式数据 | 调用restful ap返回js格式数据 | 英文词丢失: json,api |
| 14 | ascend_cs_002 | 0.130 | 嗯所以你现在还是比较focus在找工作这件事上 | 嗯所以你现在还是比较focused在找工作这件事 | 英文词丢失: focus |
| 15 | ascend_cs_001 | 0.128 | no我专业是那个i s m information systems manage… | 那我就按是那个is information systems management | 英文词丢失: i,m,no |
| 16 | cs_edge_006 | 0.125 | 用Xcode的Instruments做了一下profiling发现CPU占用太高 | 用x code的instruments做了一下prof发现cpu占用太高 | 英文词丢失: xcode,profiling, 数字/量词 |
| 17 | dev_k8s_01 | 0.121 | Kubernetes的pod状态是CrashLoopBackOff | kubernetesitis的pod状态是crash loop back off | 英文词丢失: kubernetes,crashloopbackoff |
| 18 | ascend_cs_005 | 0.109 | 所以我的我的parents我的妈妈是chemistry老师and我的爸爸是his… | 所以我的我的parents我的妈妈是chemistryry老师嗯我的爸爸是his… | 英文词丢失: chemistry,and |
| 19 | cs_error_01 | 0.107 | 这个error是null pointer exception | 这个error是no pointer exception | 英文词丢失: null |
| 20 | cs_edge_008 | 0.107 | CI pipeline跑了三十分钟还没通过unit test | c pipeline跑了三十分钟还没通过un test | 英文词丢失: unit,ci, 数字/量词 |
| 21 | cs_edge_003 | 0.098 | 用Docker Compose部署了三个microservice到staging… | 用doctorcker compose部署了三个micro service到st… | 英文词丢失: microservice,docker |
| 22 | conv_zh_001 | 0.091 | 你好我想要了解一下我的银行账户余额有多少谢谢 | 你好我想要了解一下我的银行账户的余额有多少呃谢谢 | 同音字/近音字 |
| 23 | wenet_net_009 | 0.091 | 的的需要嗯如果你把他当成产品的话你就会觉得那么消费者会需要什么样的 | 的的需要啊如果你把它当成产品的话你会觉得那么消费者会需要什么样的 | 同音字/近音字 |
| 24 | cs_edge_002 | 0.088 | 这个bug是因为race condition导致的memory leak | 这个bug是因为risk condition导致的memory leak | 英文词丢失: race |
| 25 | cs_review_01 | 0.087 | 帮我review一下这个pull request | 帮我view一下这个pull request | 英文词丢失: review |
| 26 | aishell_test_003 | 0.083 | 但因为聚集了过多公共资源 | 但因为聚集了过多公共司源 | 同音字/近音字 |
| 27 | ascend_cs_004 | 0.083 | 嗯I like hot pot | i like hot pot | 同音字/近音字 |
| 28 | cs_deploy_01 | 0.080 | 把Docker image push到registry | 把cker image push到registry | 英文词丢失: docker |
| 29 | rate_fast_01 | 0.077 | 快速语音识别测试一二三四五 | 快速语音识别测试幺二三四五 | 同音字/近音字 |
| 30 | wenet_net_006 | 0.077 | 这位叫皮特的FBI探员一上来就一顿物理分析认为阿曼达不可能吊起比她还重的女警官 | 这位叫p的fbi探员一上来就一顿物理分析认为阿曼达不可能吊起比他还重的女警官 | 同音字/近音字 |
| 31 | wenet_net_008 | 0.067 | 把这些劳工抓起来送到月亮岛上去 | 把这些劳公抓起来送到月亮岛上去 | 同音字/近音字 |
| 32 | cs_edge_005 | 0.065 | 这个function的return type应该是Optional而不是forc… | 这个function的return type应该是optional而不是forc… | 英文词丢失: force,unwrap |
| 33 | dev_db_01 | 0.062 | 执行SQL查询SELECT FROM users WHERE id等于一 | 执行cq查询select from users whereid等于一 | 英文词丢失: where,id,sql |
| 34 | wenet_net_007 | 0.061 | 她已经在商场里开起了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 | 他已经在商场里开启了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 | 同音字/近音字 |
| 35 | ascend_cs_007 | 0.059 | 对我平时然后都喜欢跟Tony一起玩 | 对我平时然后都喜欢跟ton尼一起玩 | 英文词丢失: tony |
| 36 | aishell_test_004 | 0.056 | 为了规避三四线城市明显过剩的市场风险 | 为了规避三四线城市明显过盛的市场风险 | 同音字/近音字 |
| 37 | mixed_01 | 0.053 | 我今天用Python写了一个API接口 | 我今天用python写了一个ap接口 | 英文词丢失: api |

## 6. 综合分析与建议

### 各场景最佳引擎推荐

| 场景 | 推荐引擎 | 理由 |
|------|---------|------|
| chinese_long | Qwen3-ASR (离线) | CER=0.000 |
| chinese_short | Qwen3-ASR (离线) | CER=0.000 |
| code_switching | Qwen3-ASR (离线) | CER=0.018 |
| developer_corpus | Qwen3-ASR (离线) | CER=0.070 |
| english_short | Qwen3-ASR (离线) | CER=0.000 |
| long_audio | Qwen3-ASR (离线) | CER=0.000 |
| mid_sentence_pause | Qwen3-ASR (离线) | CER=0.000 |
| mixed_technical | Qwen3-ASR (离线) | CER=0.042 |
| mixed_zh_en | Qwen3-ASR (离线) | CER=0.000 |
| punctuation | Qwen3-ASR (离线) | CER=0.000 |
| real_aishell | Qwen3-ASR (离线) | CER=0.000 |
| real_ascend_codeswitching | Qwen3-ASR (离线) | CER=0.093 |
| real_codeswitching | Qwen3-ASR (离线) | CER=0.000 |
| real_conversational | SenseVoice Nano | CER=0.068 |
| real_wenetspeech | Qwen3-ASR (流式) | CER=0.056 |
| speech_rate | Qwen3-ASR (离线) | CER=0.000 |
| speech_trailing_silence | Qwen3-ASR (离线) | CER=0.000 |
| technical_numbers | Qwen3-ASR (离线) | CER=0.080 |

### 引擎特点总结

**Qwen3-ASR (离线)**
- 平均 CER: 0.0472
- 完美识别 (CER=0): 46/70 条
- 不准确 (CER>5%): 19/70 条
- RTF: 0.092x

**Qwen3-ASR (流式)**
- 平均 CER: 0.0829
- 完美识别 (CER=0): 41/70 条
- 不准确 (CER>5%): 24/70 条
- RTF: 0.200x

**Streaming Paraformer**
- 平均 CER: 0.1128
- 完美识别 (CER=0): 16/70 条
- 不准确 (CER>5%): 45/70 条
- RTF: 0.029x

**SenseVoice Nano**
- 平均 CER: 0.0827
- 完美识别 (CER=0): 25/70 条
- 不准确 (CER>5%): 37/70 条
- RTF: 0.022x

---

*报告由 `scripts/benchmark_engines.py` 自动生成*