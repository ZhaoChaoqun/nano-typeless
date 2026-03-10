# Cloud Rewrite vs Local Rewrite 对比评估报告

*生成时间：2026-03-10 16:38*
*测试集：67 条音频（corpus.json + real_manifest.json）*
*Cloud 模型：gpt-oss-120b*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.05 | CER≤0.10 | CER>0.10 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Paraformer Pipeline | 0.1645 | 0/67 | 3 | 19 | 48 | 12.6s | 0.030x |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.0783 | 31/67 | 37 | 49 | 18 | 216.0s | 0.513x |

> Cloud API 用量：input 24194 tokens, output 17770 tokens, total 41964 tokens

## 2. 逐条对比（含文本）

### zh_short_01 (chinese_short)

**期望**: 今天天气真好。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.143 | 今天天气真好 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 今天天气真好。 |

### zh_long_01 (chinese_long)

**期望**: 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.098 | 人工智能正在深刻的改变我们的生活方式从语音识别到自动驾驶从医疗诊断到金融分析 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析。 |

### mixed_01 (mixed_zh_en)

**期望**: 我今天用 Python 写了一个 API 接口。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.100 | 我今天用python写了1个api接口 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 我今天用 python 写了一个 api 接口。 |

### mixed_02 (mixed_technical)

**期望**: MacBook Pro M3 芯片性能提升了百分之 40。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.040 | macbook pro m 3芯片性能提升了百分之40 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | MacBook Pro M3 芯片性能提升了 40%。 |

### en_short_01 (english_short)

**期望**: Hello world.

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.091** | hello world |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.091 | hello world |

### tech_num_01 (technical_numbers)

**期望**: 服务器 IP 地址是 192.168.1.100，端口号 8080。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.300 | 服务器ip地址是幺92点幺68点幺点幺00端口号8080 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 服务器 IP 地址是 192.168.1.100，端口号 8080。 |

### noise_01 (speech_trailing_silence)

**期望**: 你好。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.333 | 你好 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 你好。 |

### dev_git_01 (developer_corpus)

**期望**: 执行 git commit，修复登录 bug。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.150 | 执行git commit修复登录bu |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.050** | 执行 git commit 修复登录 bug。 |

### dev_swift_01 (developer_corpus)

**期望**: 定义一个 struct 叫做 UserModel。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.091 | 定义1个struct叫做user model |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 定义一个 struct 叫做 user model。 |

### dev_rust_01 (developer_corpus)

**期望**: 在 Rust 里面用 async await 处理并发。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.261 | 在rust里面用a think wait处理并发 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.043** | 在 Rust 里面用 async wait 处理并发。 |

### dev_k8s_01 (developer_corpus)

**期望**: Kubernetes 的 pod 状态是 CrashLoopBackOff。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.353 | cubonates的pod状态是crash back back |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.324** | cubonates 的 pod 状态是 crash back。 |

### dev_api_01 (developer_corpus)

**期望**: 调用 RESTful API 返回 JSON 格式数据。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.087 | 调用restful a p i返回js o n格式数 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 调用 RESTful API 返回 JSON 格式数据。 |

### dev_db_01 (developer_corpus)

**期望**: 执行 SQL 查询 SELECT FROM users WHERE id = 1。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.125 | 执行c ql查询select from users where i d于于 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.094** | 执行 CQL 查询 SELECT FROM users WHERE id。 |

### dev_url_01 (developer_corpus)

**期望**: 访问 github.com。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.231 | 访问github点co |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.077** | 访问 GitHub 点 com。 |

### dev_debug_01 (developer_corpus)

**期望**: 在第 42 行设置一个 breakpoint。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.100 | 在第42行设置1个break point |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 在第四十二行设置一个 break point。 |

### cs_var_01 (code_switching)

**期望**: 把这个 variable 赋值给 constant。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.043 | 把这个variable赋值给constant |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 把这个 variable 赋值给 constant。 |

### cs_build_01 (code_switching)

**期望**: 在 macOS 上运行 swift build。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.350 | 在michael s上运行swift buil |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.250** | 在 Michael S 上运行 Swift build。 |

### cs_error_01 (code_switching)

**期望**: 这个 error 是 null pointer exception。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.414** | 这个error是no pointer it se |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.414 | 这个 error 是 no pointer it says。 |

### cs_deploy_01 (code_switching)

**期望**: 把 Docker image push 到 registry。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.038 | 把docker image push到registry |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 把 docker image push 到 registry。 |

### cs_review_01 (code_switching)

**期望**: 帮我 review 一下这个 pull request。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.083 | 帮我review 1下这个pull request |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 帮我 review 一下这个 pull request。 |

### punct_question_01 (punctuation)

**期望**: 你今天吃饭了吗？

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.125 | 你今天吃饭了吗 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 你今天吃饭了吗？ |

### punct_exclaim_01 (punctuation)

**期望**: 太好了，我成功了。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.222 | 太好了我成功了 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 太好了，我成功了。 |

### punct_list_01 (punctuation)

**期望**: 第一步打开终端，第二步输入命令，第三步确认执行。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.125** | 第1步打开终端第2步输入命令第3步确认执行 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.208 | 第一步，打开终端。第二步，输入命令。第三步，确认执行。 |

### rate_fast_01 (speech_rate)

**期望**: 快速语音识别测试，1、2、3、4、5。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.316 | 快速语音识别测试12345 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.067** | 快速语音识别测试一二三四五。 |

### rate_slow_01 (speech_rate)

**期望**: 慢速语音识别测试。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.111 | 慢速语音识别测试 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 慢速语音识别测试。 |

### long_30s_01 (long_audio)

**期望**: 人工智能技术在过去 10 年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解自然语言。语音识别技术已经广泛应用于智能手机和智能音箱。自动驾驶汽车使用多种传感器和人工智能算法来感知环境。医疗领域的人工智能可以辅助医生进行疾病诊断。自然语言处理技术让机器能够理解人类的语言并做出回应。计算机视觉技术使得机器能够识别和分析图像中的内容。强化学习技术让人工智能系统能够通过试错来学习最优策略。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.057 | 人工智能技术在过去10年中取得了巨大的进步深度学习算法使得计算机能够处理和理解自然语言语音识别技术已经广泛应用于智能手机和智能音箱自动驾驶汽汽车使用多种传感器和人工智能算法来感知环境医疗领域的人工智能可以辅助医生进行疾病诊断自然语言处理技术让机器能够理解人类的语言并做出回应计算机视觉技术使得机器能够识别和分析图像中的内容强化学习技术让人工智能系统能够通过试错来学习最优优策 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 人工智能技术在过去10 年中取得了巨大的进步。深度学习算法使得计算机能够处理和理解自然语言。语音识别技术已经广泛应用于智能手机和智能音箱。自动驾驶汽车使用多种传感器和人工智能算法来感知环境。医疗领域的人工智能可以辅助医生进行疾病诊断。自然语言处理技术让机器能够理解人类的语言并做出回应。计算机视觉技术使得机器能够识别和分析图像中的内容。强化学习技术让人工智能系统能够通过试错来学习最优策略。 |

### long_60s_01 (long_audio)

**期望**: 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及到程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。版本控制系统如 Git 是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码修改。单元测试和集成测试帮助开发者在早期发现和修复缺陷。微服务架构将大型应用拆分为多个独立的小型服务。容器化技术如 Docker 简化了应用的部署和运维管理。云计算平台提供了弹性的计算资源，支持应用的快速扩展。DevOps 实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.091 | 软件工程是1门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科它涉及到程序设计语言数据库软件开发工具系统平台等方面的知识现代软件开发通常采用敏捷开发方法强调快速迭代和持续交付版本控制系统如ggit是团队协作开发的基础工具持续集成和持续部署能够自动化测试和发布流程提高开发效率代码审查是保证代码质量的重要时践团队成员互相审阅代码修改单元测试和集成测试帮助开发者在早期发现和修复缺陷微服务架构将大型应用拆分为多个独立的小型型服容器器化技术如docker简化了应用的部署和运维管理云计算平台提供了弹性的计算资源支持应用的快速扩展def ox实践将开发和运维紧密结合促进软件的快速可靠交付性能优化需要从算法数据结构系统架构等多个层面综合考虑 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.018** | 软件工程是一门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。它涉及程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。版本控制系统如 Git 是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码。单元测试和集成测试帮助开发者在早期发现和修复缺陷。微服务架构将大型应用拆分为多个独立的小型服务，容器化技术如 Docker 简化了应用的部署和运维管理。云计算平台提供弹性的计算资源，支持应用的快速扩展。DevOps 实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。 |

### pause_mid_01 (mid_sentence_pause)

**期望**: 打开终端。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.200 | 打开终端 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 打开终端。 |

### pause_long_01 (mid_sentence_pause)

**期望**: 我想要一杯咖啡。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.250 | 我想要1杯咖啡 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 我想要一杯咖啡。 |

### aishell_test_001 (real_aishell)

**期望**: 甚至出现交易几乎停滞的情况。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.071 | 甚至出现交易几乎停滞的情况 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 甚至出现交易几乎停滞的情况。 |

### aishell_test_002 (real_aishell)

**期望**: 一二线城市虽然也处于调整中。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.133 | 12线城市虽然也处于调整中 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 一二线城市虽然也处于调整中。 |

### aishell_test_003 (real_aishell)

**期望**: 但因为聚集了过多公共资源。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.077 | 但因为聚集了过多公共资源 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 但因为聚集了过多公共资源。 |

### aishell_test_004 (real_aishell)

**期望**: 为了规避三四线城市明显过剩的市场风险。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.100 | 为了规避34线城市明显过剩的市场风险 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 为了规避三四线城市明显过剩的市场风险。 |

### aishell_test_005 (real_aishell)

**期望**: 标杆房企必然调整市场战略。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.154** | 标杆房企必然调整市场占略 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.231 | 标杆房企必然调整市场占有率。 |

### aishell_test_006 (real_aishell)

**期望**: 因此，土地储备至关重要。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.167 | 因此土地储备至关重要 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 因此，土地储备至关重要。 |

### aishell_test_007 (real_aishell)

**期望**: 中原地产首席分析师张大伟说。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.071 | 中原地产首席分析师张大伟说 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 中原地产首席分析师张大伟说。 |

### aishell_test_008 (real_aishell)

**期望**: 一线城市土地供应量减少。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.167 | 1线城市土地供应量减少 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 一线城市土地供应量减少。 |

### conv_zh_001 (real_conversational)

**期望**: 你好，我想要了解一下我的银行账户余额有多少，谢谢。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.200 | 你好我想要了解1下我的银行账户的余额有多少呃谢谢 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.080** | 你好，我想了解一下我的银行账户的余额有多少，谢谢。 |

### conv_zh_004 (real_conversational)

**期望**: 我想要查询我的账户余额。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.167 | 我想要查询我的账户馀额 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 我想要查询我的账户余额。 |

### conv_zh_005 (real_conversational)

**期望**: 您好，我可以知道我的账户余额吗？

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.188 | 民好我可以知道我的账户余额吗 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 您好，我可以知道我的账户余额吗？ |

### ascend_cs_001 (real_ascend_codeswitching)

**期望**: No，我专业是那个 ISM，Information Systems Management。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.214** | 那我就暗示那个i s n information systems management |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.262 | 那我就暗示 i s n information systems management |

### ascend_cs_002 (real_ascend_codeswitching)

**期望**: 嗯，所以你现在还是比较 focus 在找工作这件事上。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.120 | 嗯所以你现在还是比较focus在找工作这件事 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.087** | 所以，你现在还是比较 focus 在找工作这件事。 |

### ascend_cs_003 (real_ascend_codeswitching)

**期望**: 深圳啊，或者是上海这种比较大的城市，会有更多 opportunity。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.324** | 深圳啊或者是上海这种表达城市会有更opportun |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.333 | 深圳或者是上海，这种表达城市会有更 opportun。 |

### ascend_cs_004 (real_ascend_codeswitching)

**期望**: 嗯，I like hot pot。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.214** | 嗯i d like hot pot |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.250 | I'd like hot pot. |

### ascend_cs_005 (real_ascend_codeswitching)

**期望**: 所以我的我的 parents，我的妈妈是 chemistry 老师，and 我的爸爸是 history 老师。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.143 | 所以我的我的parents我的妈妈是chemistry老师嗯我的爸爸是history老 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.102** | 所以，我的 parents，我的妈妈是 chemistry 老师，我的爸爸是 history 老师。 |

### ascend_cs_006 (real_ascend_codeswitching)

**期望**: 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊，一起打在就是 after class 的时候。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.339** | 那个玩玩basketball然后我就就是稍微邀我的france 1起打在就是after cast的时候 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.393 | 玩 basketball，然后我稍微邀请我的 france 一起打，正好在 after cast 的时候。 |

### ascend_cs_008 (real_ascend_codeswitching)

**期望**: 然后呃，我也喜欢 play basketball。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.130 | 然后呃我也喜play basketball |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.043** | 然后，我也喜欢 play basketball。 |

### ascend_cs_009 (real_ascend_codeswitching)

**期望**: 然后刚忘了讲，你你是念什么 major 的？

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.200** | 然后刚忘了讲1你是念什么major |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.200 | 然后刚忘了讲一下，你是念什么 major？ |

### ascend_cs_010 (real_ascend_codeswitching)

**期望**: 哦，我我在 UG 的时候念的是 electrical engineering。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.200 | 哦我我在u g的时候念的是electric engineer |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.171** | 哦，我在 UG 的时候念的是 electric engineer。 |

### wenet_net_001 (real_wenetspeech)

**期望**: 毕业歌会之后，然后我们还去吃个饭，然后就感觉。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.174** | 毕业歌会之后然后我们还去吃个饭然后就感 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.174 | 毕业歌会之后，我们去吃个饭，然后就感。 |

### wenet_net_002 (real_wenetspeech)

**期望**: 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有其他人在帮助竖锯这么做。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.231 | 数据癌症病成那样还打着点滴就更不可能把女主官吊了起来说来说去彼得认为还有其他人在帮助数据这么做 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.135** | 数据癌症病成那样，还打着点滴，就更不可能把女主官吊了起来。说来说去，彼得认为还有其他人在帮助数据这么做。 |

### wenet_net_003 (real_wenetspeech)

**期望**: 当时心里想，我只要能跪我就能站，我在床上练着跪着走。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.115** | 当时心里想我只要能跪我就能站我在床上练着跪着走 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.115 | 当时心里想，我只要能跪，我就能站。我在床上练着，跪着走。 |

### wenet_net_004 (real_wenetspeech)

**期望**: 下车后望着 30 多层的大高楼发呆。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.062** | 下车后望着30多层的大高楼发呆 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.062 | 下车后，望着三十多层的大高楼发呆。 |

### wenet_net_005 (real_wenetspeech)

**期望**: 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构模式。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.070 | 还有剧作模式的双线性叙事结尾神反转等等也成为了日后电锯惊魂系列在剧作上的结构模式 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.047** | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后《电锯惊魂》系列在剧作上的结构模式。 |

### wenet_net_006 (real_wenetspeech)

**期望**: 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.244 | 这位叫peter的f b i探员1上来就1顿物理分析认为阿曼达不可能吊起比他还重的女警官 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.146** | 这位叫 peter 的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比他还重的女警官。 |

### wenet_net_007 (real_wenetspeech)

**期望**: 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.194 | 他已经在商场里开启了小店铺尽管孤身1人但与好友见面时还是会爽朗1笑 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.083** | 他已经在商场里开启了小店铺，尽管孤身一人，但与好友见面时，还是会爽朗一笑。 |

### wenet_net_008 (real_wenetspeech)

**期望**: 把这些劳工抓起来，送到月亮岛上去。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.176 | 把这些劳工抓起来送到月亮搭上去 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.059** | 把这些劳工抓起来，送到月亮搭上去。 |

### wenet_net_009 (real_wenetspeech)

**期望**: 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | **0.200** | 的的的需要啊如果你把它当成产品的话你会会觉得那么消费者会需要什么样 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | 0.286 | 如果你把它当成产品的话，你会觉得消费者会需要什么样的？ |

### wenet_net_010 (real_wenetspeech)

**期望**: 媒体也已经报了，然后呃，债主也已经围楼了。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.190 | 媒体也已经报了然后呃债主也已经为楼了 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.053** | 媒体也已经报了，然后债主也已经为楼了。 |

### cs_edge_001 (real_codeswitching)

**期望**: 我们团队最近在用 React 和 TypeScript 重构前端项目。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.129 | 我们团队最近在用react和texcript重构前端项目 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 我们团队最近在用 React 和 TypeScript 重构前端项目。 |

### cs_edge_002 (real_codeswitching)

**期望**: 这个 bug 是因为 race condition 导致的 memory leak。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.114 | 这个bug是因为race condition导致的memory li |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 这个 bug 是因为 race condition 导致的 memory leak。 |

### cs_edge_003 (real_codeswitching)

**期望**: 用 Docker Compose 部署了 3 个 microservice 到 staging 环境。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.143 | 用darker compose部署了3个michao service到staging环 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 用 Docker Compose 部署了三个 micro service 到 staging 环境。 |

### cs_edge_004 (real_codeswitching)

**期望**: 在 GitHub 上提了一个 issue，关于 performance optimization。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.114 | 在github上提了1个约sue关于performance optimization |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0** | 在 GitHub 上提了一个 issue，关于 performance optimization。 |

### cs_edge_005 (real_codeswitching)

**期望**: 这个 function 的 return type 应该是 Optional，而不是 force unwrap。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.104 | 这个function的return tape应该是optional而不是force and rap |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.083** | 这个 function 的 return tape 应该是 optional 而不是 force and rap。 |

### cs_edge_006 (real_codeswitching)

**期望**: 用 Xcode 的 Instruments 做了一下 profiling，发现 CPU 占用太高。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.095 | 用x c o d e的instruments做了1下profiling发现cpu占用太 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.024** | 用 Xcode 的 Instruments 做了一下 profiling，发现 CPU 占用太。 |

### cs_edge_007 (real_codeswitching)

**期望**: GraphQL 的 schema 定义比 RESTful API 更灵活一些。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.121 | graph q l的schema定义笔restful api更灵活1 |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.061** | GraphQL 的 schema 定义比 RESTful API 更灵活。 |

### cs_edge_008 (real_codeswitching)

**期望**: CI pipeline 跑了 30 分钟，还没通过 unit test。

| Pipeline | CER | 输出文本 |
|----------|:---:|---------|
| Paraformer Pipeline | 0.233 | cii pipeline跑了30分钟还没通过unit |
| Paraformer + Cloud Rewrite (gpt-oss-120b) | **0.133** | CI pipeline 跑了 30 分钟，还没通过 unit。 |

## 3. Cloud vs Local 差异分析

---

*报告由 `scripts/benchmark_cloud_rewrite.py` 自动生成*