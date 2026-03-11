# Paraformer + Cloud Rewrite — CER>0 详细分析

*生成时间：2026-03-11 14:42 | 平均 CER: 0.1002 | CER=0: 19/67*

| # | ID | CER | 期望文本 | 实际输出 |
|---|-----|:---:|---------|---------|
| 1 | en_short_01 | 0.091 | Hello world. | hello world |
| 2 | noise_01 | 0.333 | 你好。 | 你好 |
| 3 | dev_git_01 | 0.050 | 执行 git commit，修复登录 bug。 | 执行 git commit 修复登录 bug。 |
| 4 | dev_rust_01 | 0.043 | 在 Rust 里面用 async await 处理并发。 | 在 Rust 里面用 async wait 处理并发。 |
| 5 | dev_k8s_01 | 0.324 | Kubernetes 的 pod 状态是 CrashLoopBackOff。 | cubonates 的 pod 状态是 crash back。 |
| 6 | dev_api_01 | 0.043 | 调用 RESTful API 返回 JSON 格式数据。 | 调用 RESTful API，返回 JSON 格式数据。 |
| 7 | dev_db_01 | 0.125 | 执行 SQL 查询 SELECT FROM users WHERE id = 1。 | 执行c ql查询select from users where id d于一 |
| 8 | dev_debug_01 | 0.050 | 在第 42 行设置一个 breakpoint。 | 在第42行设置一个break point |
| 9 | cs_build_01 | 0.250 | 在 macOS 上运行 swift build。 | 在 Michael S 上运行 Swift build。 |
| 10 | cs_error_01 | 0.241 | 这个 error 是 null pointer exception。 | 这个 error 是 no pointer in section。 |
| 11 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端。第二步，输入命令。第三步，确认执行。 |
| 12 | rate_fast_01 | 0.316 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试 12345 |
| 13 | rate_slow_01 | 0.111 | 慢速语音识别测试。 | 慢速语音识别测试 |
| 14 | long_60s_01 | 0.021 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及到程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。版本控制系统如 Git 是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码修改。单元测试和集成测试帮助开发者在早期发现和修复缺陷。微服务架构将大型应用拆分为多个独立的小型服务。容器化技术如 Docker 简化了应用的部署和运维管理。云计算平台提供了弹性的计算资源，支持应用的快速扩展。DevOps 实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。 | 软件工程是一门研究用工程化方法构建和维护有效、实用且高质量的软件的学科。它涉及程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。版本控制系统如 Git 是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码、修改。单元测试和集成测试帮助开发者在早期发现和修复缺陷。微服务架构将大型应用拆分为多个独立的小型服务，容器化技术如 Docker 简化了应用的部署和运维管理。云计算平台提供弹性的计算资源，支持应用的快速扩展。DevOps 实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。 |
| 15 | pause_mid_01 | 0.200 | 打开终端。 | 打开终端 |
| 16 | pause_long_01 | 0.125 | 我想要一杯咖啡。 | 我想要一杯咖啡 |
| 17 | aishell_test_002 | 0.133 | 一二线城市虽然也处于调整中。 | 1~2线城市虽然也处于调整中 |
| 18 | aishell_test_003 | 0.077 | 但因为聚集了过多公共资源。 | 但因为聚集了过多公共资源 |
| 19 | aishell_test_004 | 0.050 | 为了规避三四线城市明显过剩的市场风险。 | 为了规避 3~4 线城市明显过剩的市场风险。 |
| 20 | aishell_test_005 | 0.154 | 标杆房企必然调整市场战略。 | 标杆房企必然调整市场占率。 |
| 21 | aishell_test_008 | 0.083 | 一线城市土地供应量减少。 | 一线城市土地供应量减少 |
| 22 | conv_zh_001 | 0.160 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想了解我的银行账户的余额有多少，谢谢。 |
| 23 | ascend_cs_001 | 0.238 | No，我专业是那个 ISM，Information Systems Management。 | 那我就暗示 i s n information systems management。 |
| 24 | ascend_cs_002 | 0.043 | 嗯，所以你现在还是比较 focus 在找工作这件事上。 | 所以你现在还是比较 focus 在找工作这件事。 |
| 25 | ascend_cs_003 | 0.152 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportunity。 | 深圳或者是上海这种城市，会有更多 opportunity。 |
| 26 | ascend_cs_004 | 0.250 | 嗯，I like hot pot。 | I'd like hot pot. |
| 27 | ascend_cs_005 | 0.122 | 所以我的我的 parents，我的妈妈是 chemistry 老师，and 我的爸爸是 history 老师。 | 所以，我的 parents 我的妈妈是 chemistry 老师，我的爸爸是 history 老师。 |
| 28 | ascend_cs_006 | 0.268 | 那个玩 basketball 的，然后我有时候有时候会邀我的 friends 啊，一起打在就是 after class 的时候。 | 我玩 basketball，然后稍微邀请我的 friend 一起打，就是 after class 的时候。 |
| 29 | ascend_cs_008 | 0.043 | 然后呃，我也喜欢 play basketball。 | 然后，我也喜欢 play basketball。 |
| 30 | ascend_cs_009 | 0.150 | 然后刚忘了讲，你你是念什么 major 的？ | 然后，刚忘了讲一，你是念什么 major 的？ |
| 31 | ascend_cs_010 | 0.200 | 哦，我我在 UG 的时候念的是 electrical engineering。 | 哦我我在u g的时候念的是electric engineer |
| 32 | wenet_net_001 | 0.130 | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 | 毕业歌会之后然后我们还去吃个饭然后就感觉 |
| 33 | wenet_net_002 | 0.135 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说来说去，皮特认为还有其他人在帮助竖锯这么做。 | 数据癌症病成那样，还打着点滴，就更不可能把女主官吊了起来。说来说去，彼得认为还有其他人在帮助数据这么做。 |
| 34 | wenet_net_003 | 0.115 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 | 当时心里想，我只要能跪，我就能站。我在床上练着，跪着走。 |
| 35 | wenet_net_004 | 0.125 | 下车后望着 30 多层的大高楼发呆。 | 下车后，望着 30 多层的大高楼，发呆。 |
| 36 | wenet_net_005 | 0.070 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊魂系列在剧作上的结构模式。 | 还有剧作模式的双线性叙事结尾神反转等等也成为了日后电锯惊魂系列在剧作上的结构模式 |
| 37 | wenet_net_006 | 0.171 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不可能吊起比她还重的女警官。 | 这位叫 Peter 的 FBI 探员，一上来就一顿物理分析，认为阿曼达不可能吊起比他还重的女警官。 |
| 38 | wenet_net_007 | 0.139 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是会爽朗一笑。 | 他已经在商场里开启了小店铺尽管孤身一人但与好友见面时还是会爽朗一笑 |
| 39 | wenet_net_008 | 0.176 | 把这些劳工抓起来，送到月亮岛上去。 | 把这些劳工抓起来送到月亮搭上去 |
| 40 | wenet_net_009 | 0.200 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会需要什么样的。 | 的的的需要如果你把它当成产品的话你会会觉得那么消费者会需要什么样 |
| 41 | wenet_net_010 | 0.053 | 媒体也已经报了，然后呃，债主也已经围楼了。 | 媒体也已经报了，然后债主也已经为楼了。 |
| 42 | cs_edge_002 | 0.086 | 这个 bug 是因为 race condition 导致的 memory leak。 | 这个bug是因为race condition导致的memory liate |
| 43 | cs_edge_003 | 0.119 | 用 Docker Compose 部署了 3 个 microservice 到 staging 环境。 | 用darker compose部署了三个michao service到staging环境 |
| 44 | cs_edge_004 | 0.091 | 在 GitHub 上提了一个 issue，关于 performance optimization。 | 在github上提了一个约sue关于performance optimization |
| 45 | cs_edge_005 | 0.042 | 这个 function 的 return type 应该是 Optional，而不是 force unwrap。 | 这个 function 的 return type 应该是 optional，而不是 force and wrap。 |
| 46 | cs_edge_006 | 0.048 | 用 Xcode 的 Instruments 做了一下 profiling，发现 CPU 占用太高。 | 用x c o d e的instruments做了一下profiling发现cpu占用太高 |
| 47 | cs_edge_007 | 0.061 | GraphQL 的 schema 定义比 RESTful API 更灵活一些。 | graph q l的schema定义笔restful api更灵活一些 |
| 48 | cs_edge_008 | 0.300 | CI pipeline 跑了 30 分钟，还没通过 unit test。 | cii pipeline跑了30min还没通过unit |
