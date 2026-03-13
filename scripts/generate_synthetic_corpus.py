#!/usr/bin/env python3
"""
合成测试语料生成脚本

语料定义在 synthetic_corpus.yaml 中维护（~160 条）。
本脚本负责读取 YAML、生成音频、输出 synthetic_manifest.json。

用法:
    uv run --with edge-tts --with pyyaml python scripts/generate_synthetic_corpus.py
    uv run --with pyyaml python scripts/generate_synthetic_corpus.py --only-synthetic
"""

import argparse
import json
import math
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
# YAML 语料加载
# ============================================================


def load_corpus_entries(yaml_path: Path) -> list[dict]:
    """从 YAML 加载语料定义，合并 language-based TTS defaults。"""
    try:
        import yaml
    except ImportError:
        sys.exit(
            "需要 pyyaml，请使用: uv run --with pyyaml python scripts/generate_synthetic_corpus.py"
        )

    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    defaults = data.get("defaults", {})
    entries = data["entries"]

    for entry in entries:
        if not entry.get("synthetic"):
            lang_defaults = defaults.get(entry.get("language", "zh"), {})
            for key in ("say_voice", "edge_tts_voice"):
                if key not in entry and key in lang_defaults:
                    entry[key] = lang_defaults[key]

    return entries


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

    # 从 YAML 加载语料定义
    yaml_path = Path(__file__).resolve().parent / "synthetic_corpus.yaml"
    corpus_entries = load_corpus_entries(yaml_path)

    # 创建输出目录
    synthetic_dir = AUDIO_DIR / "synthetic"
    synthetic_dir.mkdir(parents=True, exist_ok=True)

    corpus_output = []

    for entry in corpus_entries:
        entry_id = entry["id"]
        et = entry.get("expected_text", "(silence)")
        text_preview = (et[0] if isinstance(et, list) else et)[:40]
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
            et = entry["expected_text"]
            text = et[0] if isinstance(et, list) else et

            if args.say:
                # macOS say 模式 (离线备选)
                say_rate = entry.get("say_rate")
                if entry.get("composite"):
                    composite_wav = synthetic_dir / f"{entry_id}.wav"
                    if generate_composite_audio(
                        entry["segments"], entry["say_voice"], composite_wav, synthetic_dir
                    ):
                        audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"
                else:
                    wav_path = synthetic_dir / f"{entry_id}.wav"
                    if generate_with_say(text, entry["say_voice"], wav_path, rate=say_rate):
                        if entry.get("trailing_silence_sec"):
                            final_wav = synthetic_dir / f"{entry_id}_with_silence.wav"
                            append_silence_to_wav(
                                wav_path, final_wav, entry["trailing_silence_sec"]
                            )
                            # 用带静音的版本替换原文件
                            final_wav.rename(wav_path)
                        audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"
            else:
                # Edge-TTS 模式 (默认)
                edge_rate = entry.get("edge_tts_rate")
                if entry.get("composite"):
                    composite_wav = synthetic_dir / f"{entry_id}.wav"
                    if generate_composite_audio(
                        entry["segments"], entry["edge_tts_voice"],
                        composite_wav, synthetic_dir
                    ):
                        audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"
                else:
                    wav_path = synthetic_dir / f"{entry_id}.wav"
                    if generate_with_edge_tts(
                        text, entry["edge_tts_voice"], wav_path, rate=edge_rate
                    ):
                        if entry.get("trailing_silence_sec"):
                            final_wav = synthetic_dir / f"{entry_id}_with_silence.wav"
                            append_silence_to_wav(
                                wav_path, final_wav, entry["trailing_silence_sec"]
                            )
                            final_wav.rename(wav_path)
                        audio_files["synthetic"] = f"audio/synthetic/{entry_id}.wav"

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

    # 写入 synthetic_manifest.json
    corpus_json = {
        "version": 2,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sample_rate": SAMPLE_RATE,
        "format": "16-bit PCM WAV, mono",
        "entries": corpus_output,
    }

    corpus_path = FIXTURES_DIR / "synthetic_manifest.json"
    with open(corpus_path, "w", encoding="utf-8") as f:
        json.dump(corpus_json, f, ensure_ascii=False, indent=2)

    # 统计
    print(f"\n{'='*60}")
    print(f"语料生成完成!")
    print(f"  synthetic_manifest.json: {corpus_path}")
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
