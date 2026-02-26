#!/usr/bin/env python3
"""
Qwen3-ASR 扩展测试语料生成脚本

35 条语料覆盖：
- 基础识别 (6) + 静音/噪声 (3)
- 开发者术语 (8)
- 中英混合 Code-Switching (5)
- 幻觉压力测试 (4)
- 标点 (3)
- 语速变化 (2)
- 长音频 (2)
- 中途停顿 (2)

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
# 语料定义：原有 9 条 + 新增 26 条
# ============================================================

CORPUS_ENTRIES = [
    # ── 原有: 基础中文 ──
    {
        "id": "zh_short_01",
        "category": "chinese_short",
        "text_input": "今天天气真好",
        "expected_text": "今天天气真好",
        "match_mode": "character_error_rate",
        "match_threshold": 0.15,
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "zh_long_01",
        "category": "chinese_long",
        "text_input": "人工智能正在深刻地改变我们的生活方式，从语音识别到自动驾驶，从医疗诊断到金融分析",
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
        "text_input": "我今天用Python写了一个API接口",
        "expected_text": "我今天用Python写了一个API接口",
        "match_mode": "contains_all",
        "match_keywords": ["Python", "API"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "mixed_02",
        "category": "mixed_technical",
        "text_input": "MacBook Pro M3芯片性能提升了百分之四十",
        "expected_text": "MacBook Pro M3芯片性能提升了百分之四十",
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
        "text_input": "Hello world",
        "expected_text": "Hello world",
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
        "text_input": "服务器IP地址是192.168.1.100端口号8080",
        "expected_text": "服务器IP地址是192.168.1.100端口号8080",
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
        "text_input": "",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 3.0,
        "synthetic": True,
    },
    {
        "id": "silence_02",
        "category": "silence_short",
        "text_input": "",
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
        "text_input": "你好",
        "expected_text": "你好",
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
        "text_input": "执行git commit修复登录bug",
        "expected_text": "执行git commit修复登录bug",
        "match_mode": "contains_all",
        "match_keywords": ["git", "commit", "bug"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_swift_01",
        "category": "developer_corpus",
        "text_input": "定义一个struct叫做UserModel",
        "expected_text": "定义一个struct叫做UserModel",
        "match_mode": "contains_all",
        "match_keywords": ["struct"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_rust_01",
        "category": "developer_corpus",
        "text_input": "在Rust里面用async await处理并发",
        "expected_text": "在Rust里面用async await处理并发",
        "match_mode": "contains_all",
        "match_keywords": ["Rust", "async"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_k8s_01",
        "category": "developer_corpus",
        "text_input": "Kubernetes的pod状态是CrashLoopBackOff",
        "expected_text": "Kubernetes的pod状态是CrashLoopBackOff",
        "match_mode": "contains_all",
        "match_keywords": ["crash", "back"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_api_01",
        "category": "developer_corpus",
        "text_input": "调用RESTful API返回JSON格式数据",
        "expected_text": "调用RESTful API返回JSON格式数据",
        "match_mode": "contains_all",
        "match_keywords": ["API", "JSON"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_db_01",
        "category": "developer_corpus",
        "text_input": "执行SQL查询SELECT FROM users WHERE id等于一",
        "expected_text": "执行SQL查询SELECT FROM users WHERE id等于一",
        "match_mode": "contains_all",
        "match_keywords": ["SQL", "SELECT", "users"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_url_01",
        "category": "developer_corpus",
        "text_input": "访问github点com",
        "expected_text": "访问github点com",
        "match_mode": "contains_all",
        "match_keywords": ["访问", "com"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "dev_debug_01",
        "category": "developer_corpus",
        "text_input": "在第四十二行设置一个breakpoint",
        "expected_text": "在第四十二行设置一个breakpoint",
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
        "text_input": "把这个variable赋值给constant",
        "expected_text": "把这个variable赋值给constant",
        "match_mode": "contains_all",
        "match_keywords": ["variable", "constant"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_build_01",
        "category": "code_switching",
        "text_input": "在macOS上运行swift build",
        "expected_text": "在macOS上运行swift build",
        "match_mode": "contains_all",
        "match_keywords": ["macOS", "swift", "build"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_error_01",
        "category": "code_switching",
        "text_input": "这个error是null pointer exception",
        "expected_text": "这个error是null pointer exception",
        "match_mode": "contains_all",
        "match_keywords": ["error", "pointer"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_deploy_01",
        "category": "code_switching",
        "text_input": "把Docker image push到registry",
        "expected_text": "把Docker image push到registry",
        "match_mode": "contains_all",
        "match_keywords": ["push", "registry"],
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "cs_review_01",
        "category": "code_switching",
        "text_input": "帮我review一下这个pull request",
        "expected_text": "帮我review一下这个pull request",
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
        "text_input": "",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 10.0,
        "synthetic": True,
    },
    {
        "id": "hal_silence_30s",
        "category": "hallucination",
        "text_input": "",
        "expected_text": "",
        "match_mode": "empty_or_whitespace",
        "language": "none",
        "duration_sec": 30.0,
        "synthetic": True,
    },
    {
        "id": "hal_white_noise_01",
        "category": "hallucination",
        "text_input": "",
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
        "text_input": "",
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
        "text_input": "你今天吃饭了吗",
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
        "text_input": "太好了我成功了",
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
        "text_input": "第一步打开终端，第二步输入命令，第三步确认执行",
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
        "text_input": "快速语音识别测试一二三四五",
        "expected_text": "快速语音识别测试一二三四五",
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
        "text_input": "慢速语音识别测试",
        "expected_text": "慢速语音识别测试",
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
        "text_input": (
            "人工智能技术在过去十年中取得了巨大的进步。"
            "深度学习算法使得计算机能够处理和理解自然语言。"
            "语音识别技术已经广泛应用于智能手机和智能音箱。"
            "自动驾驶汽车使用多种传感器和人工智能算法来感知环境。"
            "医疗领域的人工智能可以辅助医生进行疾病诊断。"
            "自然语言处理技术让机器能够理解人类的语言并做出回应。"
            "计算机视觉技术使得机器能够识别和分析图像中的内容。"
            "强化学习技术让人工智能系统能够通过试错来学习最优策略。"
        ),
        "expected_text": "人工智能",
        "match_mode": "contains",
        "language": "zh",
        "say_voice": "Tingting",
        "edge_tts_voice": "zh-CN-XiaoxiaoNeural",
    },
    {
        "id": "long_60s_01",
        "category": "long_audio",
        "text_input": (
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
        "expected_text": "软件工程",
        "match_mode": "contains",
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
        "text_input": "打开终端",
        "expected_text": "打开终端",
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
        "text_input": "我想要一杯咖啡",
        "expected_text": "我想要一杯咖啡",
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
        text_preview = entry.get("text_input", "(silence)")[:40]
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
            text = entry["text_input"]

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
            "text_input": entry["text_input"],
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
