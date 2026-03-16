# ASR Pipeline 量化对比评估报告 (Swift)

*生成时间：2026-03-12 17:28*
*测试集：184 条音频（corpus.json + real_manifest.json）*
*Pipeline：Qwen3-ASR (离线), Qwen3-ASR (流式)*
*运行方式：Swift XCTest（直接复用产品代码）*

**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。

---

## 1. 总体 CER 汇总

| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |
|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|
| Qwen3-ASR (离线) | 0.0324 | 135/184 | 159 | 178 | 6 | 137.8s | 0.161x |
| Qwen3-ASR (流式) | 0.0335 | 131/184 | 160 | 178 | 6 | 210.1s | 0.246x |

---

## 2. 按类别 CER 汇总

| 类别 | 条数 | Qwen3-ASR (离线) | Qwen3-ASR (流式) |
|------|:----:|:------:|:------:|
| chinese_long | 1 | 0.000 | 0.024 |
| chinese_short | 1 | 0.000 | 0.000 |
| code_switching | 5 | 0.017 | 0.017 |
| developer_corpus | 8 | 0.049 | 0.049 |
| english_short | 1 | 0.091 | 0.091 |
| long_audio | 2 | 0.153 | 0.036 |
| mid_sentence_pause | 2 | 0.000 | 0.000 |
| mixed_technical | 1 | 0.120 | 0.120 |
| mixed_zh_en | 1 | 0.000 | 0.000 |
| punctuation | 3 | 0.106 | 0.106 |
| qwen_streaming_bug | 1 | 0.000 | 0.000 |
| real_aishell | 8 | 0.000 | 0.000 |
| real_ascend_codeswitching | 9 | 0.053 | 0.061 |
| real_codeswitching | 8 | 0.003 | 0.003 |
| real_conversational | 3 | 0.040 | 0.133 |
| real_wenetspeech | 10 | 0.068 | 0.082 |
| speech_rate | 2 | 0.158 | 0.132 |
| speech_trailing_silence | 1 | 0.000 | 0.000 |
| td_acronym | 15 | 0.021 | 0.021 |
| td_ai_product | 15 | 0.025 | 0.042 |
| td_apple_hw | 12 | 0.004 | 0.004 |
| td_business | 10 | 0.020 | 0.008 |
| td_cn_app | 12 | 0.049 | 0.049 |
| td_db_cloud | 12 | 0.036 | 0.039 |
| td_devtool | 15 | 0.007 | 0.007 |
| td_mixed | 15 | 0.024 | 0.012 |
| td_saas_tool | 10 | 0.000 | 0.000 |
| technical_numbers | 1 | 0.600 | 0.600 |

---

## 3. 逐条 CER 详细

| # | ID | Qwen3-ASR (离线) | Qwen3-ASR (流式) | 期望文本 |
|---|-----|:------:|:------:|------|
| 1 | zh_short_01 | 0.000 | 0.000 | 今天天气真好。 |
| 2 | zh_long_01 | 0.000 | 0.024 | 人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，... |
| 3 | mixed_01 | 0.000 | 0.000 | 我今天用Python写了一个API接口。 |
| 4 | mixed_02 | 0.120 | 0.120 | MacBook Pro M3芯片性能提升了百分之40。 |
| 5 | en_short_01 | 0.091 | 0.091 | Hello world. |
| 6 | tech_num_01 | 0.600 | 0.600 | 服务器IP地址是192.168.1.100，端口号8080。 |
| 7 | noise_01 | 0.000 | 0.000 | 你好。 |
| 8 | dev_git_01 | 0.000 | 0.000 | 执行git commit，修复登录bug。 |
| 9 | dev_swift_01 | 0.000 | 0.000 | 定义一个struct叫做UserModel。 |
| 10 | dev_rust_01 | 0.043 | 0.043 | 在Rust里面用async await处理并发。 |
| 11 | dev_k8s_01 | 0.000 | 0.000 | Kubernetes的pod状态是CrashLoopBack... |
| 12 | dev_api_01 | 0.000 | 0.000 | 调用RESTful API返回JSON格式数据。 |
| 13 | dev_db_01 | 0.125 | 0.125 | 执行SQL查询SELECT FROM users WHERE... |
| 14 | dev_url_01 | 0.077 | 0.077 | 访问github.com。 |
| 15 | dev_debug_01 | 0.150 | 0.150 | 在第42行设置一个breakpoint。 |
| 16 | cs_var_01 | 0.087 | 0.087 | 把这个variable赋值给constant。 |
| 17 | cs_build_01 | 0.000 | 0.000 | 在macOS上运行swift build。 |
| 18 | cs_error_01 | 0.000 | 0.000 | 这个error是null pointer exception... |
| 19 | cs_deploy_01 | 0.000 | 0.000 | 把Docker image push到registry。 |
| 20 | cs_review_01 | 0.000 | 0.000 | 帮我review一下这个pull request。 |
| 21 | punct_question_01 | 0.000 | 0.000 | 你今天吃饭了吗？ |
| 22 | punct_exclaim_01 | 0.111 | 0.111 | 太好了，我成功了。 |
| 23 | punct_list_01 | 0.208 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 |
| 24 | rate_fast_01 | 0.316 | 0.263 | 快速语音识别测试，1、2、3、4、5。 |
| 25 | rate_slow_01 | 0.000 | 0.000 | 慢速语音识别测试。 |
| 26 | long_30s_01 | 0.010 | 0.026 | 人工智能技术在过去10年中取得了巨大的进步。深度学习算法使得... |
| 27 | long_60s_01 | 0.296 | 0.047 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量... |
| 28 | pause_mid_01 | 0.000 | 0.000 | 打开终端。 |
| 29 | pause_long_01 | 0.000 | 0.000 | 我想要一杯咖啡。 |
| 30 | td_acronym_01 | 0.000 | 0.000 | 调用API返回JSON格式数据。 |
| 31 | td_acronym_02 | 0.000 | 0.000 | 通过HTTP请求访问URL地址。 |
| 32 | td_acronym_03 | 0.000 | 0.000 | HTTPS比HTTP更安全。 |
| 33 | td_acronym_04 | 0.067 | 0.067 | 配置CI/CD流水线自动部署。 |
| 34 | td_acronym_05 | 0.000 | 0.000 | LLM和NLP是人工智能的核心技术。 |
| 35 | td_acronym_06 | 0.000 | 0.000 | GPU加速比CPU快很多倍。 |
| 36 | td_acronym_07 | 0.000 | 0.000 | 使用SSH连接远程服务器。 |
| 37 | td_acronym_08 | 0.143 | 0.143 | RAG技术结合了检索和生成。 |
| 38 | td_acronym_09 | 0.000 | 0.000 | RLHF是大模型对齐的关键方法。 |
| 39 | td_acronym_10 | 0.000 | 0.000 | 用SDK集成第三方支付功能。 |
| 40 | td_acronym_11 | 0.000 | 0.000 | TTS和ASR是语音技术的两大方向。 |
| 41 | td_acronym_12 | 0.000 | 0.000 | 通过VPN连接公司内网。 |
| 42 | td_acronym_13 | 0.111 | 0.111 | BERT模型在NER任务上表现很好。 |
| 43 | td_acronym_14 | 0.000 | 0.000 | ORM框架简化了SQL操作。 |
| 44 | td_acronym_15 | 0.000 | 0.000 | 用JWT实现OAuth认证。 |
| 45 | td_ai_product_01 | 0.000 | 0.000 | ChatGPT是OpenAI开发的对话模型。 |
| 46 | td_ai_product_02 | 0.000 | 0.000 | Claude是Anthropic推出的AI助手。 |
| 47 | td_ai_product_03 | 0.000 | 0.000 | DeepSeek的推理模型性能很强。 |
| 48 | td_ai_product_04 | 0.000 | 0.000 | 用Midjourney生成一张插图。 |
| 49 | td_ai_product_05 | 0.000 | 0.000 | Stable Diffusion可以本地运行。 |
| 50 | td_ai_product_06 | 0.000 | 0.000 | Copilot帮我写了一段代码。 |
| 51 | td_ai_product_07 | 0.000 | 0.000 | LangChain用于构建LLM应用。 |
| 52 | td_ai_product_08 | 0.000 | 0.000 | Hugging Face上有很多开源模型。 |
| 53 | td_ai_product_09 | 0.211 | 0.211 | 用Ollama在本地跑LLaMA模型。 |
| 54 | td_ai_product_10 | 0.000 | 0.000 | Whisper是OpenAI的语音识别模型。 |
| 55 | td_ai_product_11 | 0.000 | 0.062 | 文心一言和通义千问是国产大模型。 |
| 56 | td_ai_product_12 | 0.000 | 0.000 | 豆包是字节跳动的AI助手。 |
| 57 | td_ai_product_13 | 0.000 | 0.000 | Gemini是Google的多模态模型。 |
| 58 | td_ai_product_14 | 0.000 | 0.188 | Qwen是阿里巴巴的开源大模型。 |
| 59 | td_ai_product_15 | 0.167 | 0.167 | Kimi擅长处理长文本。 |
| 60 | td_apple_01 | 0.000 | 0.000 | 在MacBook Pro上安装Xcode。 |
| 61 | td_apple_02 | 0.000 | 0.000 | iPhone和iPad都运行iOS系统。 |
| 62 | td_apple_03 | 0.000 | 0.000 | AirPods连接到iCloud账号。 |
| 63 | td_apple_04 | 0.000 | 0.000 | macOS和iPadOS共享很多功能。 |
| 64 | td_apple_05 | 0.000 | 0.000 | Apple Watch支持watchOS系统。 |
| 65 | td_apple_06 | 0.045 | 0.045 | 把Wi-Fi密码分享给MacBook Air。 |
| 66 | td_apple_07 | 0.000 | 0.000 | NVIDIA的GPU性能领先AMD。 |
| 67 | td_apple_08 | 0.000 | 0.000 | SSD比HDD读写速度快很多。 |
| 68 | td_apple_09 | 0.000 | 0.000 | 用HDMI线连接到OLED显示器。 |
| 69 | td_apple_10 | 0.000 | 0.000 | USB接口支持数据传输和充电。 |
| 70 | td_apple_11 | 0.000 | 0.000 | Tesla和SpaceX都是马斯克的公司。 |
| 71 | td_apple_12 | 0.000 | 0.000 | VR和AR技术在游戏中广泛应用。 |
| 72 | td_cn_app_01 | 0.000 | 0.000 | 在抖音上看到一个有趣的视频。 |
| 73 | td_cn_app_02 | 0.000 | 0.000 | 小红书上有很多好的笔记。 |
| 74 | td_cn_app_03 | 0.471 | 0.471 | bilibili上有很多编程教程。 |
| 75 | td_cn_app_04 | 0.000 | 0.000 | 用WeChat给朋友发消息。 |
| 76 | td_cn_app_05 | 0.118 | 0.118 | 在淘宝上买东西用Alipay付款。 |
| 77 | td_cn_app_06 | 0.000 | 0.000 | 美团外卖和滴滴打车很方便。 |
| 78 | td_cn_app_07 | 0.000 | 0.000 | 拼多多的百亿补贴很划算。 |
| 79 | td_cn_app_08 | 0.000 | 0.000 | 腾讯和百度都在做AI大模型。 |
| 80 | td_cn_app_09 | 0.000 | 0.000 | 华为和小米是国产手机品牌。 |
| 81 | td_cn_app_10 | 0.000 | 0.000 | 京东物流配送速度很快。 |
| 82 | td_cn_app_11 | 0.000 | 0.000 | 用飞书和钉钉开视频会议。 |
| 83 | td_cn_app_12 | 0.000 | 0.000 | 在微博上看热搜新闻。 |
| 84 | td_devtool_01 | 0.000 | 0.000 | 在VS Code里安装ESLint插件。 |
| 85 | td_devtool_02 | 0.000 | 0.000 | 用TypeScript开发React前端项目。 |
| 86 | td_devtool_03 | 0.000 | 0.000 | Node.js后端用Express框架。 |
| 87 | td_devtool_04 | 0.000 | 0.000 | Vue.js和Angular都是前端框架。 |
| 88 | td_devtool_05 | 0.045 | 0.045 | FastAPI比Django更适合做微服务。 |
| 89 | td_devtool_06 | 0.000 | 0.000 | 用Docker部署Kubernetes集群。 |
| 90 | td_devtool_07 | 0.000 | 0.000 | Terraform和Ansible管理云基础设施。 |
| 91 | td_devtool_08 | 0.053 | 0.053 | 在GitHub上提交PR等待代码审查。 |
| 92 | td_devtool_09 | 0.000 | 0.000 | 用Webpack打包JavaScript代码。 |
| 93 | td_devtool_10 | 0.000 | 0.000 | Vite比Webpack构建速度更快。 |
| 94 | td_devtool_11 | 0.000 | 0.000 | Flutter可以同时开发iOS和Android应用。 |
| 95 | td_devtool_12 | 0.000 | 0.000 | React Native和Swift都能开发手机应用。 |
| 96 | td_devtool_13 | 0.000 | 0.000 | 用Postman测试GraphQL接口。 |
| 97 | td_devtool_14 | 0.000 | 0.000 | Homebrew是macOS上的包管理器。 |
| 98 | td_devtool_15 | 0.000 | 0.000 | Next.js用于服务端渲染的React应用。 |
| 99 | td_db_cloud_01 | 0.000 | 0.000 | MySQL和PostgreSQL都是关系型数据库。 |
| 100 | td_db_cloud_02 | 0.000 | 0.000 | MongoDB是流行的NoSQL数据库。 |
| 101 | td_db_cloud_03 | 0.000 | 0.000 | Redis做缓存，Kafka做消息队列。 |
| 102 | td_db_cloud_04 | 0.000 | 0.000 | Elasticsearch支持全文搜索功能。 |
| 103 | td_db_cloud_05 | 0.071 | 0.071 | 部署在AWS上用CDN加速。 |
| 104 | td_db_cloud_06 | 0.000 | 0.000 | Cloudflare提供DNS和CDN服务。 |
| 105 | td_db_cloud_07 | 0.136 | 0.136 | Vercel部署Next.js应用非常方便。 |
| 106 | td_db_cloud_08 | 0.087 | 0.087 | 用Supabase替代Firebase做后端。 |
| 107 | td_db_cloud_09 | 0.000 | 0.000 | Prometheus监控加Grafana看板。 |
| 108 | td_db_cloud_10 | 0.000 | 0.045 | Milvus和Pinecone是向量数据库。 |
| 109 | td_db_cloud_11 | 0.133 | 0.133 | Nginx做反向代理非常稳定。 |
| 110 | td_db_cloud_12 | 0.000 | 0.000 | ClickHouse适合OLAP分析场景。 |
| 111 | td_biz_01 | 0.000 | 0.000 | 公司的KPI和OKR要按季度制定。 |
| 112 | td_biz_02 | 0.000 | 0.000 | 这个MVP产品需要做POC验证。 |
| 113 | td_biz_03 | 0.000 | 0.000 | SaaS产品关注ARR和MRR指标。 |
| 114 | td_biz_04 | 0.000 | 0.000 | 投资ROI达到了百分之二十。 |
| 115 | td_biz_05 | 0.077 | 0.077 | 签了NDA之后才能看文档。 |
| 116 | td_biz_06 | 0.000 | 0.000 | 公司准备IPO上市了。 |
| 117 | td_biz_07 | 0.000 | 0.000 | CRM系统管理客户关系。 |
| 118 | td_biz_08 | 0.000 | 0.000 | ERP系统整合了HR和财务模块。 |
| 119 | td_biz_09 | 0.125 | 0.000 | SLA要求服务可用性达到四个九。 |
| 120 | td_biz_10 | 0.000 | 0.000 | 制定标准的SOP操作流程。 |
| 121 | td_saas_01 | 0.000 | 0.000 | 在Notion里写文档，用Figma做设计。 |
| 122 | td_saas_02 | 0.000 | 0.000 | Slack消息和Jira任务要同步。 |
| 123 | td_saas_03 | 0.000 | 0.000 | Trello看板管理项目进度。 |
| 124 | td_saas_04 | 0.000 | 0.000 | 用Zoom开远程会议。 |
| 125 | td_saas_05 | 0.000 | 0.000 | Obsidian是很好的笔记工具。 |
| 126 | td_saas_06 | 0.000 | 0.000 | Linear比Jira更轻量级。 |
| 127 | td_saas_07 | 0.000 | 0.000 | YouTube和Netflix是视频平台。 |
| 128 | td_saas_08 | 0.000 | 0.000 | Spotify上有很多播客节目。 |
| 129 | td_saas_09 | 0.000 | 0.000 | Dropbox和iCloud都是云存储。 |
| 130 | td_saas_10 | 0.000 | 0.000 | 用Sentry监控线上错误日志。 |
| 131 | td_mixed_01 | 0.000 | 0.000 | 在GitHub上用Copilot写TypeScript代码。 |
| 132 | td_mixed_02 | 0.000 | 0.000 | ChatGPT的API通过HTTPS协议调用。 |
| 133 | td_mixed_03 | 0.000 | 0.000 | 用PyTorch在GPU上训练LLM模型。 |
| 134 | td_mixed_04 | 0.000 | 0.000 | iPhone上安装了WeChat和抖音。 |
| 135 | td_mixed_05 | 0.000 | 0.000 | DevOps团队用Docker和Kubernetes做CI/... |
| 136 | td_mixed_06 | 0.000 | 0.000 | Stack Overflow上有很多React和Vue.js... |
| 137 | td_mixed_07 | 0.000 | 0.000 | 用TensorFlow和ONNX部署深度学习模型。 |
| 138 | td_mixed_08 | 0.182 | 0.000 | 阿里巴巴的Qwen和百度的文心一言都在竞争。 |
| 139 | td_mixed_09 | 0.133 | 0.133 | 在Vercel上部署用Prisma连接PostgreSQL。 |
| 140 | td_mixed_10 | 0.000 | 0.000 | Microsoft收购了GitHub和LinkedIn。 |
| 141 | td_mixed_11 | 0.000 | 0.000 | Stripe和PayPal是主要的支付网关。 |
| 142 | td_mixed_12 | 0.043 | 0.043 | 在Discord上讨论Web3和DeFi项目。 |
| 143 | td_mixed_13 | 0.000 | 0.000 | Airbnb和Uber改变了出行和住宿行业。 |
| 144 | td_mixed_14 | 0.000 | 0.000 | NVIDIA的GPU运行vLLM做推理服务。 |
| 145 | td_mixed_15 | 0.000 | 0.000 | Shopify用Cloudflare做CDN加速。 |
| 146 | repro_qwen_repeat_01 | 0.000 | 0.000 | 帮我写一个Python脚本，读取这个CSV文件，按date字... |
| 147 | aishell_test_001 | 0.000 | 0.000 | 甚至出现交易几乎停滞的情况。 |
| 148 | aishell_test_002 | 0.000 | 0.000 | 一二线城市虽然也处于调整中。 |
| 149 | aishell_test_003 | 0.000 | 0.000 | 但因为聚集了过多公共资源。 |
| 150 | aishell_test_004 | 0.000 | 0.000 | 为了规避三四线城市明显过剩的市场风险。 |
| 151 | aishell_test_005 | 0.000 | 0.000 | 标杆房企必然调整市场战略。 |
| 152 | aishell_test_006 | 0.000 | 0.000 | 因此，土地储备至关重要。 |
| 153 | aishell_test_007 | 0.000 | 0.000 | 中原地产首席分析师张大伟说。 |
| 154 | aishell_test_008 | 0.000 | 0.000 | 一线城市土地供应量减少。 |
| 155 | conv_zh_001 | 0.120 | 0.400 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 |
| 156 | conv_zh_004 | 0.000 | 0.000 | 我想要查询我的账户余额。 |
| 157 | conv_zh_005 | 0.000 | 0.000 | 您好，我可以知道我的账户余额吗？ |
| 158 | ascend_cs_001 | 0.071 | 0.071 | No，我专业是那个 ISM，Information Syst... |
| 159 | ascend_cs_002 | 0.040 | 0.040 | 嗯，所以你现在还是比较 focus 在找工作这件事上。 |
| 160 | ascend_cs_003 | 0.000 | 0.000 | 深圳啊，或者是上海这种比较大的城市，会有更多 opportu... |
| 161 | ascend_cs_004 | 0.000 | 0.071 | 嗯，I like hot pot。 |
| 162 | ascend_cs_005 | 0.061 | 0.061 | 所以我的我的 parents，我的妈妈是 chemistry... |
| 163 | ascend_cs_006 | 0.158 | 0.158 | 那个玩 basketball 的，然后我有时候有时候会邀我的... |
| 164 | ascend_cs_008 | 0.043 | 0.043 | 然后呃，我也喜欢 play basketball。 |
| 165 | ascend_cs_009 | 0.050 | 0.050 | 然后刚忘了讲，你你是念什么 major 的？ |
| 166 | ascend_cs_010 | 0.057 | 0.057 | 哦，我我在 UG 的时候念的是 electrical eng... |
| 167 | wenet_net_001 | 0.000 | 0.000 | 毕业歌会之后，然后我们还去吃个饭，然后就感觉。 |
| 168 | wenet_net_002 | 0.115 | 0.135 | 竖锯癌症病成那样，还打着点滴，就更不可能把女警官吊了起来。说... |
| 169 | wenet_net_003 | 0.115 | 0.115 | 当时心里想，我只要能跪我就能站，我在床上练着跪着走。 |
| 170 | wenet_net_004 | 0.062 | 0.062 | 下车后望着 30 多层的大高楼发呆。 |
| 171 | wenet_net_005 | 0.047 | 0.047 | 还有剧作模式的双线性叙事、结尾神反转等等，也成为了日后电锯惊... |
| 172 | wenet_net_006 | 0.122 | 0.122 | 这位叫皮特的 FBI 探员一上来就一顿物理分析，认为阿曼达不... |
| 173 | wenet_net_007 | 0.028 | 0.028 | 她已经在商场里开起了小店铺，尽管孤身一人，但与好友见面时还是... |
| 174 | wenet_net_008 | 0.000 | 0.118 | 把这些劳工抓起来，送到月亮岛上去。 |
| 175 | wenet_net_009 | 0.143 | 0.143 | 的的需要。嗯，如果你把他当成产品的话，你就会觉得那么消费者会... |
| 176 | wenet_net_010 | 0.048 | 0.048 | 媒体也已经报了，然后呃，债主也已经围楼了。 |
| 177 | cs_edge_001 | 0.000 | 0.000 | 我们团队最近在用 React 和 TypeScript 重构... |
| 178 | cs_edge_002 | 0.000 | 0.000 | 这个 bug 是因为 race condition 导致的 ... |
| 179 | cs_edge_003 | 0.000 | 0.000 | 用 Docker Compose 部署了 3 个 micro... |
| 180 | cs_edge_004 | 0.023 | 0.023 | 在 GitHub 上提了一个 issue，关于 perfor... |
| 181 | cs_edge_005 | 0.000 | 0.000 | 这个 function 的 return type 应该是 ... |
| 182 | cs_edge_006 | 0.000 | 0.000 | 用 Xcode 的 Instruments 做了一下 pro... |
| 183 | cs_edge_007 | 0.000 | 0.000 | GraphQL 的 schema 定义比 RESTful A... |
| 184 | cs_edge_008 | 0.000 | 0.000 | CI pipeline 跑了 30 分钟，还没通过 unit... |

---

## 4. 高 CER 条目详情 (CER > 0.20)

### Qwen3-ASR (离线)

| # | ID | CER | 期望文本 | 实际输出 | 分析 |
|---|-----|:---:|---------|---------|------|
| 1 | tech_num_01 | 0.600 | 服务器IP地址是192.168.1.100，端口号8080。 | 服务器 IP 地址是幺九二点幺六八点幺点幺零零，端口号八千零八十。 | |
| 2 | td_cn_app_03 | 0.471 | bilibili上有很多编程教程。 | 哔哩哔哩上有很多编程教程。 | |
| 3 | rate_fast_01 | 0.316 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试：一、二、三、四、五。 | |
| 4 | long_60s_01 | 0.296 | 软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。它涉及到程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。版本控制系统如Git是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码修改。单元测试和集成测试帮助开发者在早期发现和修复缺陷。微服务架构将大型应用拆分为多个独立的小型服务。容器化技术如Docker简化了应用的部署和运维管理。云计算平台提供了弹性的计算资源，支持应用的快速扩展。DevOps实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。 | 软件工程是一门研究用工程化方法构建和维护有效的、实用的和高质量的软件的学科。它涉及到程序设计语言、数据库、软件开发工具、系统平台等方面的知识。现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。 版本控制系统如Git是团队协作开发的基础工具。持续集成和持续部署能够自动化测试和发布流程，提高开发效率。代码审查是保证代码质量的重要实践，团队成员互相审阅代码修改。 DevOps实践将开发和运维紧密结合，促进软件的快速可靠交付。性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。 | |
| 5 | td_ai_product_09 | 0.211 | 用Ollama在本地跑LLaMA模型。 | 用 Alma 在本地跑 Lama 模型。 | |
| 6 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端；第二步，输入命令；第三步，确认执行。 | |

### Qwen3-ASR (流式)

| # | ID | CER | 期望文本 | 实际输出 | 分析 |
|---|-----|:---:|---------|---------|------|
| 1 | tech_num_01 | 0.600 | 服务器IP地址是192.168.1.100，端口号8080。 | 服务器IP地址是幺九二点幺六八点幺点幺零零，端口号八千零八十。 | |
| 2 | td_cn_app_03 | 0.471 | bilibili上有很多编程教程。 | 哔哩哔哩上有很多编程教程。 | |
| 3 | conv_zh_001 | 0.400 | 你好，我想要了解一下我的银行账户余额有多少，谢谢。 | 你好，我想要了解一下我的銀行帳戶的餘額有多少？呃，謝謝。 | |
| 4 | rate_fast_01 | 0.263 | 快速语音识别测试，1、2、3、4、5。 | 快速语音识别测试，一、二、三、四、五。 | |
| 5 | td_ai_product_09 | 0.211 | 用Ollama在本地跑LLaMA模型。 | 用 Alma 在本地跑 Lama 模型。 | |
| 6 | punct_list_01 | 0.208 | 第一步打开终端，第二步输入命令，第三步确认执行。 | 第一步，打开终端；第二步，输入命令；第三步，确认执行。 | |
