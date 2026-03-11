#!/usr/bin/env python3
"""
Qwen3-ASR 扩展测试语料生成脚本

~151 条语料覆盖：
- 基础识别 (6) + 静音/噪声 (3)
- 开发者术语 (8)
- 中英混合 Code-Switching (5)
- 幻觉压力测试 (4)
- 标点 (3)
- 语速变化 (2)
- 长音频 (2)
- 中途停顿 (2)
- term_dictionary 覆盖 (~106):
  - 缩写折叠 (15)
  - AI 产品/模型 (15)
  - Apple 生态 & 硬件 (12)
  - 中文互联网 APP (12)
  - 开发工具 & 框架 (15)
  - 数据库 & 云服务 (12)
  - 商业 & 金融 (10)
  - 协作 & SaaS 工具 (10)
  - 综合混合场景 (15)

默认使用 Edge-TTS 生成高质量语音，合成音频（静音/噪声）不需要网络。

用法:
    uv run --with edge-tts python scripts/generate_extended_corpus.py
    uv run --with edge-tts python scripts/generate_extended_corpus.py --only-synthetic
"""

import argparse
import json
import os
import random
import struct
import subprocess
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = PROJECT_ROOT / "tests" / "fixtures"
AUDIO_DIR = FIXTURES_DIR / "audio"
SAMPLE_RATE = 16000

# ============================================================
# 语料定义：原有 35 条 + term_dictionary 覆盖 116 条
# ============================================================

CORPUS_ENTRIES = [
    # ── 原有: 基础中文 ──
    {
        "id": "zh_short_01",
        "category": "chinese_short",
        "expected_text": "今天天气真好。",
        "match_mode": "character_error_rate",
        "match_threshold": 0.15,
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "zh_long_01",
        "category": "chinese_long",
        "expected_text": "人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析。",
        "match_mode": "character_error_rate",
        "match_threshold": 0.15,
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    # ── 原有: 中英混合 ──
    {
        "id": "mixed_01",
        "category": "mixed_zh_en",
        "expected_text": "我今天用Python写了一个API接口。",
        "match_mode": "contains_all",
        "match_keywords": ["Python", "API"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "mixed_02",
        "category": "mixed_technical",
        "expected_text": "MacBook Pro M3芯片性能提升了百分之40。",
        "match_mode": "contains_all",
        "match_keywords": ["MacBook", "芯片"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    # ── 原有: 英文 ──
    {
        "id": "en_short_01",
        "category": "english_short",
        "expected_text": "Hello world.",
        "match_mode": "character_error_rate",
        "match_threshold": 0.2,
        "language": "en",
        "say_voice": "Samantha",
        "edge_tts_voice": "en-US-JennyNeural",
    },
    # ── 原有: 数字技术 ──
    {
        "id": "tech_num_01",
        "category": "technical_numbers",
        "expected_text": "服务器IP地址是192.168.1.100，端口号8080。",
        "match_mode": "contains_all",
        "match_keywords": ["服务器", "端口"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    # ── 原有: 静音 ──
    {
        "id": "silence_01",
        "category": "silence",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 3.0,
        "synthetic": True,
    },
    {
        "id": "silence_02",
        "category": "silence_short",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 0.1,
        "synthetic": True,
    },
    # ── 原有: 语音+尾部静音 ──
    {
        "id": "noise_01",
        "category": "speech_trailing_silence",
        "expected_text": "你好。",
        "match_mode": "contains",
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
        "trailing_silence_sec": 5.0,
    },

    # ============================================================
    # 新增: 开发者术语 (8 条)
    # ============================================================
    {
        "id": "dev_git_01",
        "category": "developer_corpus",
        "expected_text": "执行git commit，修复登录bug。",
        "match_mode": "contains_all",
        "match_keywords": ["git", "commit", "bug"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_swift_01",
        "category": "developer_corpus",
        "expected_text": "定义一个struct叫做UserModel。",
        "match_mode": "contains_all",
        "match_keywords": ["struct"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_rust_01",
        "category": "developer_corpus",
        "expected_text": "在Rust里面用async await处理并发。",
        "match_mode": "contains_all",
        "match_keywords": ["Rust", "async"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_k8s_01",
        "category": "developer_corpus",
        "expected_text": "Kubernetes的pod状态是CrashLoopBackOff。",
        "match_mode": "contains_all",
        "match_keywords": ["crash", "back"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_api_01",
        "category": "developer_corpus",
        "expected_text": "调用RESTful API返回JSON格式数据。",
        "match_mode": "contains_all",
        "match_keywords": ["API", "JSON"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_db_01",
        "category": "developer_corpus",
        "expected_text": "执行SQL查询SELECT FROM users WHERE id = 1。",
        "match_mode": "contains_all",
        "match_keywords": ["SQL", "SELECT", "users"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_url_01",
        "category": "developer_corpus",
        "expected_text": "访问github.com。",
        "match_mode": "contains_all",
        "match_keywords": ["访问", "com"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_debug_01",
        "category": "developer_corpus",
        "expected_text": "在第42行设置一个breakpoint。",
        "match_mode": "contains_all",
        "match_keywords": ["breakpoint"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ============================================================
    # 新增: Code-Switching 句内中英混合 (5 条)
    # ============================================================
    {
        "id": "cs_var_01",
        "category": "code_switching",
        "expected_text": "把这个variable赋值给constant。",
        "match_mode": "contains_all",
        "match_keywords": ["variable", "constant"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_build_01",
        "category": "code_switching",
        "expected_text": "在macOS上运行swift build。",
        "match_mode": "contains_all",
        "match_keywords": ["macOS", "swift", "build"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_error_01",
        "category": "code_switching",
        "expected_text": "这个error是null pointer exception。",
        "match_mode": "contains_all",
        "match_keywords": ["error", "pointer"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_deploy_01",
        "category": "code_switching",
        "expected_text": "把Docker image push到registry。",
        "match_mode": "contains_all",
        "match_keywords": ["push", "registry"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_review_01",
        "category": "code_switching",
        "expected_text": "帮我review一下这个pull request。",
        "match_mode": "contains_all",
        "match_keywords": ["review", "pull", "request"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ============================================================
    # 新增: 幻觉压力测试 (4 条)
    # ============================================================
    {
        "id": "hal_silence_10s",
        "category": "hallucination",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 10.0,
        "synthetic": True,
    },
    {
        "id": "hal_silence_30s",
        "category": "hallucination",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 30.0,
        "synthetic": True,
    },
    {
        "id": "hal_white_noise_01",
        "category": "hallucination",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 3.0,
        "synthetic": True,
        "noise_type": "white",
        "noise_amplitude": 0.005,
    },
    {
        "id": "hal_breath_01",
        "category": "hallucination",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 3.0,
        "synthetic": True,
        "noise_type": "breath",
    },

    # ============================================================
    # 新增: 标点 & 格式 (3 条)
    # ============================================================
    {
        "id": "punct_question_01",
        "category": "punctuation",
        "expected_text": "你今天吃饭了吗？",
        "match_mode": "contains_all",
        "match_keywords": ["吃饭", "？"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "punct_exclaim_01",
        "category": "punctuation",
        "expected_text": "太好了，我成功了。",
        "match_mode": "contains_all",
        "match_keywords": ["成功", "，"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "punct_list_01",
        "category": "punctuation",
        "expected_text": "第一步打开终端，第二步输入命令，第三步确认执行。",
        "match_mode": "contains_all",
        "match_keywords": ["终端", "命令", "，"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ============================================================
    # 新增: 语速变化 (2 条)
    # ============================================================
    {
        "id": "rate_fast_01",
        "category": "speech_rate",
        "expected_text": "快速语音识别测试，1、2、3、4、5。",
        "match_mode": "character_error_rate",
        "match_threshold": 0.2,
        "language": "zh",
        "say_voice": "Tingting",
        "say_rate": 280,
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
        "edge_tts_rate": "+60%",
    },
    {
        "id": "rate_slow_01",
        "category": "speech_rate",
        "expected_text": "慢速语音识别测试。",
        "match_mode": "character_error_rate",
        "match_threshold": 0.15,
        "language": "zh",
        "say_voice": "Tingting",
        "say_rate": 100,
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
        "edge_tts_rate": "-40%",
    },

    # ============================================================
    # 新增: 长音频 (2 条)
    # ============================================================
    {
        "id": "long_30s_01",
        "category": "long_audio",
        "expected_text": (
            "人工智能技术在过去10年中取得了巨大的进步。"
            "深度学习算法使得计算机能够处理和理解自然语言。"
            "语音识别技术已经广泛应用于智能手机和智能音箱。"
            "自动驾驶汽车使用多种传感器和人工智能算法来感知环境。"
            "医疗领域的人工智能可以辅助医生进行疾病诊断。"
            "自然语言处理技术让机器能够理解人类的语言并做出回应。"
            "计算机视觉技术使得机器能够识别和分析图像中的内容。"
            "强化学习技术让人工智能系统能够通过试错来学习最优策略。"
        ),
        "match_mode": "character_error_rate",
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "long_60s_01",
        "category": "long_audio",
        "expected_text": (
            "软件工程是一门研究用工程化方法构建和维护有效的实用的和高质量的软件的学科。"
            "它涉及到程序设计语言、数据库、软件开发工具、系统平台等方面的知识。"
            "现代软件开发通常采用敏捷开发方法，强调快速迭代和持续交付。"
            "版本控制系统如Git是团队协作开发的基础工具。"
            "持续集成和持续部署能够自动化测试和发布流程，提高开发效率。"
            "代码审查是保证代码质量的重要实践，团队成员互相审阅代码修改。"
            "单元测试和集成测试帮助开发者在早期发现和修复缺陷。"
            "微服务架构将大型应用拆分为多个独立的小型服务。"
            "容器化技术如Docker简化了应用的部署和运维管理。"
            "云计算平台提供了弹性的计算资源，支持应用的快速扩展。"
            "DevOps实践将开发和运维紧密结合，促进软件的快速可靠交付。"
            "性能优化需要从算法、数据结构、系统架构等多个层面综合考虑。"
        ),
        "match_mode": "character_error_rate",
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ============================================================
    # 新增: 中途停顿 (2 条) — 使用 composite 模式
    # ============================================================
    {
        "id": "pause_mid_01",
        "category": "mid_sentence_pause",
        "expected_text": "打开终端。",
        "match_mode": "contains_all",
        "match_keywords": ["打开", "终端"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
        "composite": True,
        "segments": [
            {"text": "打开", "pause_after_sec": 2.0},
            {"text": "终端", "pause_after_sec": 0},
        ],
    },
    {
        "id": "pause_long_01",
        "category": "mid_sentence_pause",
        "expected_text": "我想要一杯咖啡。",
        "match_mode": "contains_all",
        "match_keywords": ["想", "咖啡"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
        "composite": True,
        "segments": [
            {"text": "我想要", "pause_after_sec": 5.0},
            {"text": "一杯咖啡", "pause_after_sec": 0},
        ],
    },

    # ============================================================
    # term_dictionary 覆盖测试 (~100 条)
    # ============================================================

    # ── 缩写折叠 (15 条) ──
    {
        "id": "td_acronym_01",
        "category": "td_acronym",
        "expected_text": "调用API返回JSON格式数据。",
        "match_mode": "contains_all",
        "match_keywords": ["API", "JSON"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_02",
        "category": "td_acronym",
        "expected_text": "通过HTTP请求访问URL地址。",
        "match_mode": "contains_all",
        "match_keywords": ["HTTP", "URL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_03",
        "category": "td_acronym",
        "expected_text": "HTTPS比HTTP更安全。",
        "match_mode": "contains_all",
        "match_keywords": ["HTTPS", "HTTP"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_04",
        "category": "td_acronym",
        "expected_text": "配置CI/CD流水线自动部署。",
        "match_mode": "contains_all",
        "match_keywords": ["CI", "CD"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_05",
        "category": "td_acronym",
        "expected_text": "LLM和NLP是人工智能的核心技术。",
        "match_mode": "contains_all",
        "match_keywords": ["LLM", "NLP"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_06",
        "category": "td_acronym",
        "expected_text": "GPU加速比CPU快很多倍。",
        "match_mode": "contains_all",
        "match_keywords": ["GPU", "CPU"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_07",
        "category": "td_acronym",
        "expected_text": "使用SSH连接远程服务器。",
        "match_mode": "contains_all",
        "match_keywords": ["SSH"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_08",
        "category": "td_acronym",
        "expected_text": "RAG技术结合了检索和生成。",
        "match_mode": "contains_all",
        "match_keywords": ["RAG"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_09",
        "category": "td_acronym",
        "expected_text": "RLHF是大模型对齐的关键方法。",
        "match_mode": "contains_all",
        "match_keywords": ["RLHF"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_10",
        "category": "td_acronym",
        "expected_text": "用SDK集成第三方支付功能。",
        "match_mode": "contains_all",
        "match_keywords": ["SDK"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_11",
        "category": "td_acronym",
        "expected_text": "TTS和ASR是语音技术的两大方向。",
        "match_mode": "contains_all",
        "match_keywords": ["TTS", "ASR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_12",
        "category": "td_acronym",
        "expected_text": "通过VPN连接公司内网。",
        "match_mode": "contains_all",
        "match_keywords": ["VPN"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_13",
        "category": "td_acronym",
        "expected_text": "BERT模型在NER任务上表现很好。",
        "match_mode": "contains_all",
        "match_keywords": ["BERT", "NER"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_14",
        "category": "td_acronym",
        "expected_text": "ORM框架简化了SQL操作。",
        "match_mode": "contains_all",
        "match_keywords": ["ORM", "SQL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_acronym_15",
        "category": "td_acronym",
        "expected_text": "用JWT实现OAuth认证。",
        "match_mode": "contains_all",
        "match_keywords": ["JWT", "OAuth"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── AI 产品/模型 (15 条) ──
    {
        "id": "td_ai_product_01",
        "category": "td_ai_product",
        "expected_text": "ChatGPT是OpenAI开发的对话模型。",
        "match_mode": "contains_all",
        "match_keywords": ["ChatGPT", "OpenAI"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_02",
        "category": "td_ai_product",
        "expected_text": "Claude是Anthropic推出的AI助手。",
        "match_mode": "contains_all",
        "match_keywords": ["Claude", "Anthropic"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_03",
        "category": "td_ai_product",
        "expected_text": "DeepSeek的推理模型性能很强。",
        "match_mode": "contains_all",
        "match_keywords": ["DeepSeek"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_04",
        "category": "td_ai_product",
        "expected_text": "用Midjourney生成一张插图。",
        "match_mode": "contains_all",
        "match_keywords": ["Midjourney"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_05",
        "category": "td_ai_product",
        "expected_text": "Stable Diffusion可以本地运行。",
        "match_mode": "contains_all",
        "match_keywords": ["Stable", "Diffusion"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_06",
        "category": "td_ai_product",
        "expected_text": "Copilot帮我写了一段代码。",
        "match_mode": "contains_all",
        "match_keywords": ["Copilot"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_07",
        "category": "td_ai_product",
        "expected_text": "LangChain用于构建LLM应用。",
        "match_mode": "contains_all",
        "match_keywords": ["LangChain", "LLM"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_08",
        "category": "td_ai_product",
        "expected_text": "Hugging Face上有很多开源模型。",
        "match_mode": "contains_all",
        "match_keywords": ["Hugging", "Face"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_09",
        "category": "td_ai_product",
        "expected_text": "用Ollama在本地跑LLaMA模型。",
        "match_mode": "contains_all",
        "match_keywords": ["Ollama", "LLaMA"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_10",
        "category": "td_ai_product",
        "expected_text": "Whisper是OpenAI的语音识别模型。",
        "match_mode": "contains_all",
        "match_keywords": ["Whisper", "OpenAI"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_11",
        "category": "td_ai_product",
        "expected_text": "文心一言和通义千问是国产大模型。",
        "match_mode": "contains_all",
        "match_keywords": ["文心一言", "通义千问"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_12",
        "category": "td_ai_product",
        "expected_text": "豆包是字节跳动的AI助手。",
        "match_mode": "contains_all",
        "match_keywords": ["豆包", "字节跳动"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_13",
        "category": "td_ai_product",
        "expected_text": "Gemini是Google的多模态模型。",
        "match_mode": "contains_all",
        "match_keywords": ["Gemini", "Google"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_14",
        "category": "td_ai_product",
        "expected_text": "Qwen是阿里巴巴的开源大模型。",
        "match_mode": "contains_all",
        "match_keywords": ["Qwen", "阿里巴巴"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_ai_product_15",
        "category": "td_ai_product",
        "expected_text": "Kimi擅长处理长文本。",
        "match_mode": "contains_all",
        "match_keywords": ["Kimi"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── Apple 生态 & 硬件 (12 条) ──
    {
        "id": "td_apple_01",
        "category": "td_apple_hw",
        "expected_text": "在MacBook Pro上安装Xcode。",
        "match_mode": "contains_all",
        "match_keywords": ["MacBook", "Xcode"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_02",
        "category": "td_apple_hw",
        "expected_text": "iPhone和iPad都运行iOS系统。",
        "match_mode": "contains_all",
        "match_keywords": ["iPhone", "iPad", "iOS"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_03",
        "category": "td_apple_hw",
        "expected_text": "AirPods连接到iCloud账号。",
        "match_mode": "contains_all",
        "match_keywords": ["AirPods", "iCloud"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_04",
        "category": "td_apple_hw",
        "expected_text": "macOS和iPadOS共享很多功能。",
        "match_mode": "contains_all",
        "match_keywords": ["macOS", "iPadOS"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_05",
        "category": "td_apple_hw",
        "expected_text": "Apple Watch支持watchOS系统。",
        "match_mode": "contains_all",
        "match_keywords": ["Apple", "Watch", "watchOS"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_06",
        "category": "td_apple_hw",
        "expected_text": "把Wi-Fi密码分享给MacBook Air。",
        "match_mode": "contains_all",
        "match_keywords": ["Wi-Fi", "MacBook"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_07",
        "category": "td_apple_hw",
        "expected_text": "NVIDIA的GPU性能领先AMD。",
        "match_mode": "contains_all",
        "match_keywords": ["NVIDIA", "GPU", "AMD"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_08",
        "category": "td_apple_hw",
        "expected_text": "SSD比HDD读写速度快很多。",
        "match_mode": "contains_all",
        "match_keywords": ["SSD", "HDD"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_09",
        "category": "td_apple_hw",
        "expected_text": "用HDMI线连接到OLED显示器。",
        "match_mode": "contains_all",
        "match_keywords": ["HDMI", "OLED"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_10",
        "category": "td_apple_hw",
        "expected_text": "USB接口支持数据传输和充电。",
        "match_mode": "contains_all",
        "match_keywords": ["USB"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_11",
        "category": "td_apple_hw",
        "expected_text": "Tesla和SpaceX都是马斯克的公司。",
        "match_mode": "contains_all",
        "match_keywords": ["Tesla", "SpaceX"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_apple_12",
        "category": "td_apple_hw",
        "expected_text": "VR和AR技术在游戏中广泛应用。",
        "match_mode": "contains_all",
        "match_keywords": ["VR", "AR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 中文互联网 APP (12 条) ──
    {
        "id": "td_cn_app_01",
        "category": "td_cn_app",
        "expected_text": "在抖音上看到一个有趣的视频。",
        "match_mode": "contains_all",
        "match_keywords": ["抖音"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_02",
        "category": "td_cn_app",
        "expected_text": "小红书上有很多好的笔记。",
        "match_mode": "contains_all",
        "match_keywords": ["小红书"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_03",
        "category": "td_cn_app",
        "expected_text": "bilibili上有很多编程教程。",
        "match_mode": "contains_all",
        "match_keywords": ["bilibili"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_04",
        "category": "td_cn_app",
        "expected_text": "用WeChat给朋友发消息。",
        "match_mode": "contains_all",
        "match_keywords": ["WeChat"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_05",
        "category": "td_cn_app",
        "expected_text": "在淘宝上买东西用Alipay付款。",
        "match_mode": "contains_all",
        "match_keywords": ["淘宝", "Alipay"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_06",
        "category": "td_cn_app",
        "expected_text": "美团外卖和滴滴打车很方便。",
        "match_mode": "contains_all",
        "match_keywords": ["美团", "滴滴"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_07",
        "category": "td_cn_app",
        "expected_text": "拼多多的百亿补贴很划算。",
        "match_mode": "contains_all",
        "match_keywords": ["拼多多"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_08",
        "category": "td_cn_app",
        "expected_text": "腾讯和百度都在做AI大模型。",
        "match_mode": "contains_all",
        "match_keywords": ["腾讯", "百度"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_09",
        "category": "td_cn_app",
        "expected_text": "华为和小米是国产手机品牌。",
        "match_mode": "contains_all",
        "match_keywords": ["华为", "小米"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_10",
        "category": "td_cn_app",
        "expected_text": "京东物流配送速度很快。",
        "match_mode": "contains_all",
        "match_keywords": ["京东"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_11",
        "category": "td_cn_app",
        "expected_text": "用飞书和钉钉开视频会议。",
        "match_mode": "contains_all",
        "match_keywords": ["飞书", "钉钉"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_cn_app_12",
        "category": "td_cn_app",
        "expected_text": "在微博上看热搜新闻。",
        "match_mode": "contains_all",
        "match_keywords": ["微博"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 开发工具 & 框架 (15 条) ──
    {
        "id": "td_devtool_01",
        "category": "td_devtool",
        "expected_text": "在VS Code里安装ESLint插件。",
        "match_mode": "contains_all",
        "match_keywords": ["VS Code", "ESLint"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_02",
        "category": "td_devtool",
        "expected_text": "用TypeScript开发React前端项目。",
        "match_mode": "contains_all",
        "match_keywords": ["TypeScript", "React"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_03",
        "category": "td_devtool",
        "expected_text": "Node.js后端用Express框架。",
        "match_mode": "contains_all",
        "match_keywords": ["Node.js", "Express"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_04",
        "category": "td_devtool",
        "expected_text": "Vue.js和Angular都是前端框架。",
        "match_mode": "contains_all",
        "match_keywords": ["Vue", "Angular"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_05",
        "category": "td_devtool",
        "expected_text": "FastAPI比Django更适合做微服务。",
        "match_mode": "contains_all",
        "match_keywords": ["FastAPI", "Django"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_06",
        "category": "td_devtool",
        "expected_text": "用Docker部署Kubernetes集群。",
        "match_mode": "contains_all",
        "match_keywords": ["Docker", "Kubernetes"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_07",
        "category": "td_devtool",
        "expected_text": "Terraform和Ansible管理云基础设施。",
        "match_mode": "contains_all",
        "match_keywords": ["Terraform", "Ansible"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_08",
        "category": "td_devtool",
        "expected_text": "在GitHub上提交PR等待代码审查。",
        "match_mode": "contains_all",
        "match_keywords": ["GitHub", "PR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_09",
        "category": "td_devtool",
        "expected_text": "用Webpack打包JavaScript代码。",
        "match_mode": "contains_all",
        "match_keywords": ["Webpack", "JavaScript"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_10",
        "category": "td_devtool",
        "expected_text": "Vite比Webpack构建速度更快。",
        "match_mode": "contains_all",
        "match_keywords": ["Vite", "Webpack"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_11",
        "category": "td_devtool",
        "expected_text": "Flutter可以同时开发iOS和Android应用。",
        "match_mode": "contains_all",
        "match_keywords": ["Flutter", "iOS", "Android"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_12",
        "category": "td_devtool",
        "expected_text": "React Native和Swift都能开发手机应用。",
        "match_mode": "contains_all",
        "match_keywords": ["React Native", "Swift"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_13",
        "category": "td_devtool",
        "expected_text": "用Postman测试GraphQL接口。",
        "match_mode": "contains_all",
        "match_keywords": ["Postman", "GraphQL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_14",
        "category": "td_devtool",
        "expected_text": "Homebrew是macOS上的包管理器。",
        "match_mode": "contains_all",
        "match_keywords": ["Homebrew", "macOS"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_devtool_15",
        "category": "td_devtool",
        "expected_text": "Next.js用于服务端渲染的React应用。",
        "match_mode": "contains_all",
        "match_keywords": ["Next.js", "React"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 数据库 & 云服务 (12 条) ──
    {
        "id": "td_db_cloud_01",
        "category": "td_db_cloud",
        "expected_text": "MySQL和PostgreSQL都是关系型数据库。",
        "match_mode": "contains_all",
        "match_keywords": ["MySQL", "PostgreSQL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_02",
        "category": "td_db_cloud",
        "expected_text": "MongoDB是流行的NoSQL数据库。",
        "match_mode": "contains_all",
        "match_keywords": ["MongoDB", "NoSQL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_03",
        "category": "td_db_cloud",
        "expected_text": "Redis做缓存，Kafka做消息队列。",
        "match_mode": "contains_all",
        "match_keywords": ["Redis", "Kafka"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_04",
        "category": "td_db_cloud",
        "expected_text": "Elasticsearch支持全文搜索功能。",
        "match_mode": "contains_all",
        "match_keywords": ["Elasticsearch"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_05",
        "category": "td_db_cloud",
        "expected_text": "部署在AWS上用CDN加速。",
        "match_mode": "contains_all",
        "match_keywords": ["AWS", "CDN"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_06",
        "category": "td_db_cloud",
        "expected_text": "Cloudflare提供DNS和CDN服务。",
        "match_mode": "contains_all",
        "match_keywords": ["Cloudflare", "DNS", "CDN"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_07",
        "category": "td_db_cloud",
        "expected_text": "Vercel部署Next.js应用非常方便。",
        "match_mode": "contains_all",
        "match_keywords": ["Vercel", "Next.js"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_08",
        "category": "td_db_cloud",
        "expected_text": "用Supabase替代Firebase做后端。",
        "match_mode": "contains_all",
        "match_keywords": ["Supabase", "Firebase"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_09",
        "category": "td_db_cloud",
        "expected_text": "Prometheus监控加Grafana看板。",
        "match_mode": "contains_all",
        "match_keywords": ["Prometheus", "Grafana"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_10",
        "category": "td_db_cloud",
        "expected_text": "Milvus和Pinecone是向量数据库。",
        "match_mode": "contains_all",
        "match_keywords": ["Milvus", "Pinecone"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_11",
        "category": "td_db_cloud",
        "expected_text": "Nginx做反向代理非常稳定。",
        "match_mode": "contains_all",
        "match_keywords": ["Nginx"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_db_cloud_12",
        "category": "td_db_cloud",
        "expected_text": "ClickHouse适合OLAP分析场景。",
        "match_mode": "contains_all",
        "match_keywords": ["ClickHouse"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 商业 & 金融 (10 条) ──
    {
        "id": "td_biz_01",
        "category": "td_business",
        "expected_text": "公司的KPI和OKR要按季度制定。",
        "match_mode": "contains_all",
        "match_keywords": ["KPI", "OKR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_02",
        "category": "td_business",
        "expected_text": "这个MVP产品需要做POC验证。",
        "match_mode": "contains_all",
        "match_keywords": ["MVP", "POC"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_03",
        "category": "td_business",
        "expected_text": "SaaS产品关注ARR和MRR指标。",
        "match_mode": "contains_all",
        "match_keywords": ["SaaS", "ARR", "MRR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_04",
        "category": "td_business",
        "expected_text": "投资ROI达到了百分之二十。",
        "match_mode": "contains_all",
        "match_keywords": ["ROI"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_05",
        "category": "td_business",
        "expected_text": "签了NDA之后才能看文档。",
        "match_mode": "contains_all",
        "match_keywords": ["NDA"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_06",
        "category": "td_business",
        "expected_text": "公司准备IPO上市了。",
        "match_mode": "contains_all",
        "match_keywords": ["IPO"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_07",
        "category": "td_business",
        "expected_text": "CRM系统管理客户关系。",
        "match_mode": "contains_all",
        "match_keywords": ["CRM"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_08",
        "category": "td_business",
        "expected_text": "ERP系统整合了HR和财务模块。",
        "match_mode": "contains_all",
        "match_keywords": ["ERP", "HR"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_09",
        "category": "td_business",
        "expected_text": "SLA要求服务可用性达到四个九。",
        "match_mode": "contains_all",
        "match_keywords": ["SLA"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_biz_10",
        "category": "td_business",
        "expected_text": "制定标准的SOP操作流程。",
        "match_mode": "contains_all",
        "match_keywords": ["SOP"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 协作 & SaaS 工具 (10 条) ──
    {
        "id": "td_saas_01",
        "category": "td_saas_tool",
        "expected_text": "在Notion里写文档，用Figma做设计。",
        "match_mode": "contains_all",
        "match_keywords": ["Notion", "Figma"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_02",
        "category": "td_saas_tool",
        "expected_text": "Slack消息和Jira任务要同步。",
        "match_mode": "contains_all",
        "match_keywords": ["Slack", "Jira"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_03",
        "category": "td_saas_tool",
        "expected_text": "Trello看板管理项目进度。",
        "match_mode": "contains_all",
        "match_keywords": ["Trello"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_04",
        "category": "td_saas_tool",
        "expected_text": "用Zoom开远程会议。",
        "match_mode": "contains_all",
        "match_keywords": ["Zoom"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_05",
        "category": "td_saas_tool",
        "expected_text": "Obsidian是很好的笔记工具。",
        "match_mode": "contains_all",
        "match_keywords": ["Obsidian"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_06",
        "category": "td_saas_tool",
        "expected_text": "Linear比Jira更轻量级。",
        "match_mode": "contains_all",
        "match_keywords": ["Linear", "Jira"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_07",
        "category": "td_saas_tool",
        "expected_text": "YouTube和Netflix是视频平台。",
        "match_mode": "contains_all",
        "match_keywords": ["YouTube", "Netflix"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_08",
        "category": "td_saas_tool",
        "expected_text": "Spotify上有很多播客节目。",
        "match_mode": "contains_all",
        "match_keywords": ["Spotify"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_09",
        "category": "td_saas_tool",
        "expected_text": "Dropbox和iCloud都是云存储。",
        "match_mode": "contains_all",
        "match_keywords": ["Dropbox", "iCloud"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_saas_10",
        "category": "td_saas_tool",
        "expected_text": "用Sentry监控线上错误日志。",
        "match_mode": "contains_all",
        "match_keywords": ["Sentry"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },

    # ── 综合混合场景 (15 条) ──
    {
        "id": "td_mixed_01",
        "category": "td_mixed",
        "expected_text": "在GitHub上用Copilot写TypeScript代码。",
        "match_mode": "contains_all",
        "match_keywords": ["GitHub", "Copilot", "TypeScript"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_02",
        "category": "td_mixed",
        "expected_text": "ChatGPT的API通过HTTPS协议调用。",
        "match_mode": "contains_all",
        "match_keywords": ["ChatGPT", "API", "HTTPS"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_03",
        "category": "td_mixed",
        "expected_text": "用PyTorch在GPU上训练LLM模型。",
        "match_mode": "contains_all",
        "match_keywords": ["PyTorch", "GPU", "LLM"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_04",
        "category": "td_mixed",
        "expected_text": "iPhone上安装了WeChat和抖音。",
        "match_mode": "contains_all",
        "match_keywords": ["iPhone", "WeChat", "抖音"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_05",
        "category": "td_mixed",
        "expected_text": "DevOps团队用Docker和Kubernetes做CI/CD。",
        "match_mode": "contains_all",
        "match_keywords": ["DevOps", "Docker", "Kubernetes"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_06",
        "category": "td_mixed",
        "expected_text": "Stack Overflow上有很多React和Vue.js的问题。",
        "match_mode": "contains_all",
        "match_keywords": ["Stack Overflow", "React", "Vue"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_07",
        "category": "td_mixed",
        "expected_text": "用TensorFlow和ONNX部署深度学习模型。",
        "match_mode": "contains_all",
        "match_keywords": ["TensorFlow", "ONNX"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_08",
        "category": "td_mixed",
        "expected_text": "阿里巴巴的Qwen和百度的文心一言都在竞争。",
        "match_mode": "contains_all",
        "match_keywords": ["阿里巴巴", "Qwen", "百度", "文心一言"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_09",
        "category": "td_mixed",
        "expected_text": "在Vercel上部署用Prisma连接PostgreSQL。",
        "match_mode": "contains_all",
        "match_keywords": ["Vercel", "Prisma", "PostgreSQL"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_10",
        "category": "td_mixed",
        "expected_text": "Microsoft收购了GitHub和LinkedIn。",
        "match_mode": "contains_all",
        "match_keywords": ["Microsoft", "GitHub", "LinkedIn"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_11",
        "category": "td_mixed",
        "expected_text": "Stripe和PayPal是主要的支付网关。",
        "match_mode": "contains_all",
        "match_keywords": ["Stripe", "PayPal"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_12",
        "category": "td_mixed",
        "expected_text": "在Discord上讨论Web3和DeFi项目。",
        "match_mode": "contains_all",
        "match_keywords": ["Discord", "Web3", "DeFi"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_13",
        "category": "td_mixed",
        "expected_text": "Airbnb和Uber改变了出行和住宿行业。",
        "match_mode": "contains_all",
        "match_keywords": ["Airbnb", "Uber"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_14",
        "category": "td_mixed",
        "expected_text": "NVIDIA的GPU运行vLLM做推理服务。",
        "match_mode": "contains_all",
        "match_keywords": ["NVIDIA", "GPU", "vLLM"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "td_mixed_15",
        "category": "td_mixed",
        "expected_text": "Shopify用Cloudflare做CDN加速。",
        "match_mode": "contains_all",
        "match_keywords": ["Shopify", "Cloudflare", "CDN"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
]


# ============================================================
# 音频生成函数
# ============================================================


def generate_silence_wav(output_path: Path, duration_sec: float):
    """生成纯静音 WAV 文件"""
    n_samples = int(SAMPLE_RATE * duration_sec)
    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(b"\x00\x00" * n_samples)
    print(f"  [synthetic] {output_path.name} ({duration_sec}s silence)")


def generate_white_noise_wav(output_path: Path, duration_sec: float, amplitude: float = 0.005):
    """生成低振幅白噪声 WAV 文件"""
    n_samples = int(SAMPLE_RATE * duration_sec)
    max_val = int(amplitude * 32767)
    samples = bytes()
    for _ in range(n_samples):
        val = random.randint(-max_val, max_val)
        samples += struct.pack("<h", val)
    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(samples)
    print(f"  [synthetic] {output_path.name} ({duration_sec}s white noise, amp={amplitude})")


def generate_breath_noise_wav(output_path: Path, duration_sec: float):
    """生成模拟呼吸声的噪声 WAV（短脉冲 + 静音交替）"""
    n_samples = int(SAMPLE_RATE * duration_sec)
    samples = bytearray(n_samples * 2)  # 16-bit = 2 bytes per sample

    # 每 1.5 秒一次"呼吸"，每次持续 0.3 秒
    breath_interval = int(1.5 * SAMPLE_RATE)
    breath_duration = int(0.3 * SAMPLE_RATE)

    for i in range(n_samples):
        pos_in_cycle = i % breath_interval
        if pos_in_cycle < breath_duration:
            # 呼吸脉冲：低频 + 噪声
            import math
            base = math.sin(2 * math.pi * 80 * i / SAMPLE_RATE)  # 80Hz 低频
            noise = random.uniform(-1, 1) * 0.003
            val = int((base * 0.002 + noise) * 32767)
            val = max(-32767, min(32767, val))
        else:
            val = 0
        struct.pack_into("<h", samples, i * 2, val)

    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(bytes(samples))
    print(f"  [synthetic] {output_path.name} ({duration_sec}s breath noise)")


def append_silence_to_wav(input_path: Path, output_path: Path, silence_sec: float):
    """在 WAV 文件末尾追加静音"""
    with wave.open(str(input_path), "rb") as wf_in:
        params = wf_in.getparams()
        audio_data = wf_in.readframes(wf_in.getnframes())

    n_silence_samples = int(SAMPLE_RATE * silence_sec)
    silence_data = b"\x00\x00" * n_silence_samples

    with wave.open(str(output_path), "wb") as wf_out:
        wf_out.setparams(params)
        wf_out.writeframes(audio_data + silence_data)
    print(f"  [synthetic] {output_path.name} (+{silence_sec}s trailing silence)")


def generate_with_say(text: str, voice: str, output_path: Path, rate: int | None = None) -> bool:
    """使用 macOS say 命令生成音频"""
    aiff_path = output_path.with_suffix(".aiff")
    try:
        cmd = ["say", "-v", voice, "-o", str(aiff_path)]
        if rate is not None:
            cmd.extend(["-r", str(rate)])
        cmd.append(text)

        subprocess.run(cmd, check=True, capture_output=True)
        subprocess.run(
            [
                "afconvert",
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                str(aiff_path),
                str(output_path),
            ],
            check=True,
            capture_output=True,
        )
        aiff_path.unlink(missing_ok=True)
        rate_info = f", rate={rate}" if rate else ""
        print(f"  [say/{voice}{rate_info}] {output_path.name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  [say] FAILED: {e}", file=sys.stderr)
        aiff_path.unlink(missing_ok=True)
        return False


def generate_with_edge_tts(text: str, voice: str, output_path: Path, rate: str | None = None) -> bool:
    """使用 edge-tts 生成音频"""
    mp3_path = output_path.with_suffix(".mp3")
    try:
        cmd = [
            "uv", "run", "--with", "edge-tts",
            "edge-tts",
            "--voice", voice,
            "--write-media", str(mp3_path),
            "--text", text,
        ]
        if rate is not None:
            cmd.extend([f"--rate={rate}"])

        subprocess.run(cmd, check=True, capture_output=True, timeout=120)
        subprocess.run(
            [
                "afconvert",
                "-f", "WAVE",
                "-d", "LEI16@16000",
                "-c", "1",
                str(mp3_path),
                str(output_path),
            ],
            check=True,
            capture_output=True,
        )
        mp3_path.unlink(missing_ok=True)
        print(f"  [edge-tts/{voice}] {output_path.name}")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as e:
        print(f"  [edge-tts] FAILED: {e}", file=sys.stderr)
        mp3_path.unlink(missing_ok=True)
        return False


def generate_composite_audio(
    segments: list[dict], voice: str, output_path: Path, work_dir: Path
) -> bool:
    """生成带中途停顿的复合音频：多段语音 + 静音间隔拼接"""
    all_audio_data = b""

    for i, seg in enumerate(segments):
        text = seg["text"]
        pause_after = seg.get("pause_after_sec", 0)

        # 为每段生成临时 WAV (使用 Edge-TTS)
        seg_path = work_dir / f"_tmp_seg_{i}.wav"
        if not generate_with_edge_tts(text, voice, seg_path):
            return False

        with wave.open(str(seg_path), "rb") as wf:
            all_audio_data += wf.readframes(wf.getnframes())
        seg_path.unlink(missing_ok=True)

        # 添加静音间隔
        if pause_after > 0:
            n_silence = int(SAMPLE_RATE * pause_after)
            all_audio_data += b"\x00\x00" * n_silence

    # 写入最终 WAV
    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(all_audio_data)

    print(f"  [composite] {output_path.name} ({len(segments)} segments)")
    return True


def get_wav_duration(path: Path) -> float:
    """获取 WAV 文件时长"""
    try:
        with wave.open(str(path), "rb") as wf:
            return wf.getnframes() / wf.getframerate()
    except Exception:
        return 0.0


# ============================================================
# 主函数
# ============================================================


def main():
    parser = argparse.ArgumentParser(description="生成 Qwen3-ASR 扩展测试语料")
    parser.add_argument(
        "--say",
        action="store_true",
        help="使用 macOS say 而非 edge-tts (离线备选)",
    )
    parser.add_argument(
        "--only-synthetic",
        action="store_true",
        help="仅生成合成音频（静音、噪声等），跳过 TTS",
    )
    args = parser.parse_args()

    # 固定随机种子以保证可重现
    random.seed(42)

    # 创建输出目录
    edge_tts_dir = AUDIO_DIR / "edge_tts"
    say_dir = AUDIO_DIR / "say"
    synthetic_dir = AUDIO_DIR / "synthetic"
    for d in [edge_tts_dir, say_dir, synthetic_dir]:
        d.mkdir(parents=True, exist_ok=True)

    corpus_output = []

    for entry in CORPUS_ENTRIES:
        entry_id = entry["id"]
        text_preview = entry.get("expected_text", "(silence)")[:40]
        print(f"\n[{entry_id}] {text_preview}")

        audio_files = {}

        if entry.get("synthetic"):
            wav_path = synthetic_dir / f"{entry_id}.wav"
            noise_type = entry.get("noise_type")

            if noise_type == "white":
                generate_white_noise_wav(
                    wav_path,
                    entry["duration_sec"],
                    entry.get("noise_amplitude", 0.005),
                )
            elif noise_type == "breath":
                generate_breath_noise_wav(wav_path, entry["duration_sec"])
            else:
                generate_silence_wav(wav_path, entry["duration_sec"])

            audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"

        elif not args.only_synthetic:
            text = entry["expected_text"]

            if args.say:
                # macOS say 模式 (离线备选)
                say_rate = entry.get("say_rate")
                if entry.get("composite"):
                    composite_wav = say_dir / f"{entry_id}.wav"
                    if generate_composite_audio(
                        entry["segments"], entry["say_voice"], composite_wav, say_dir
                    ):
                        audio_files["say"] = f"audio/say/{entry_id}.wav"
                else:
                    say_wav = say_dir / f"{entry_id}.wav"
                    if generate_with_say(text, entry["say_voice"], say_wav, rate=say_rate):
                        if entry.get("trailing_silence_sec"):
                            final_wav = synthetic_dir / f"{entry_id}.wav"
                            append_silence_to_wav(
                                say_wav, final_wav, entry["trailing_silence_sec"]
                            )
                            audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"
                        audio_files["say"] = f"audio/say/{entry_id}.wav"
            else:
                # Edge-TTS 模式 (默认)
                edge_rate = entry.get("edge_tts_rate")
                if entry.get("composite"):
                    composite_wav = edge_tts_dir / f"{entry_id}.wav"
                    if generate_composite_audio(
                        entry["segments"], entry["edge_tts_voice"],
                        composite_wav, edge_tts_dir
                    ):
                        audio_files["edge_tts"] = f"audio/edge_tts/{entry_id}.wav"
                else:
                    edge_wav = edge_tts_dir / f"{entry_id}.wav"
                    if generate_with_edge_tts(
                        text, entry["edge_tts_voice"], edge_wav, rate=edge_rate
                    ):
                        if entry.get("trailing_silence_sec"):
                            final_wav = synthetic_dir / f"{entry_id}.wav"
                            append_silence_to_wav(
                                edge_wav, final_wav, entry["trailing_silence_sec"]
                            )
                            audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"
                        audio_files["edge_tts"] = f"audio/edge_tts/{entry_id}.wav"

        # 计算时长
        duration = 0.0
        for _key, rel_path in audio_files.items():
            full_path = FIXTURES_DIR / rel_path
            if full_path.exists():
                duration = get_wav_duration(full_path)
                break
        if entry.get("duration_sec") and duration == 0.0:
            duration = entry["duration_sec"]

        # 构建 corpus entry
        corpus_entry = {
            "id": entry_id,
            "category": entry["category"],
            "expected_text": entry["expected_text"],
            "match_mode": entry["match_mode"],
            "audio_files": audio_files,
            "duration_sec": round(duration, 2),
            "language": entry["language"],
        }
        if entry.get("match_keywords"):
            corpus_entry["match_keywords"] = entry["match_keywords"]
        if entry.get("match_threshold"):
            corpus_entry["match_threshold"] = entry["match_threshold"]

        corpus_output.append(corpus_entry)

    # 写入 corpus.json
    corpus_json = {
        "version": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sample_rate": SAMPLE_RATE,
        "format": "16-bit PCM WAV, mono",
        "entries": corpus_output,
    }

    corpus_path = FIXTURES_DIR / "corpus.json"
    with open(corpus_path, "w", encoding="utf-8") as f:
        json.dump(corpus_json, f, ensure_ascii=False, indent=2)

    # 统计
    print(f"\n{'='*60}")
    print(f"语料生成完成!")
    print(f"  corpus.json: {corpus_path}")
    print(f"  条目总数: {len(corpus_output)}")

    categories = {}
    for e in corpus_output:
        cat = e["category"]
        categories[cat] = categories.get(cat, 0) + 1

    print(f"\n  分类统计:")
    for cat, count in sorted(categories.items()):
        print(f"    {cat}: {count}")

    total_audio = sum(len(e["audio_files"]) for e in corpus_output)
    print(f"\n  音频文件总数: {total_audio}")

    for entry in corpus_output:
        sources = ", ".join(entry["audio_files"].keys()) or "(none)"
        print(f"  [{entry['id']}] {sources} - {entry['duration_sec']}s")


if __name__ == "__main__":
    main()
