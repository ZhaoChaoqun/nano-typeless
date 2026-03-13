#!/usr/bin/env python3
"""
Download and prepare recorded ASR test data for Qwen3-ASR evaluation.

Sources:
  1. AISHELL-1 test split (8 samples) — standard Mandarin benchmark
  2. MINDS-14 zh-CN (5 samples) — real conversational recordings
  3. ASCEND test split (10 samples) — real Chinese-English code-switching
  4. WenetSpeech TEST_NET (10 samples) — multi-scene Chinese (gated dataset)

Usage:
    # Full run (requires network + HuggingFace datasets)
    uv run --with 'datasets[audio]' --with soundfile --with scipy \
        python scripts/download_recorded_corpus.py

    # Skip WenetSpeech (if no HuggingFace authorization)
    uv run --with 'datasets[audio]' --with soundfile --with scipy \
        python scripts/download_recorded_corpus.py --skip-wenetspeech
"""

import argparse
import json
import struct
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = PROJECT_ROOT / "tests" / "fixtures"
REAL_AUDIO_DIR = FIXTURES_DIR / "audio" / "recorded"
SAMPLE_RATE = 16000


# ============================================================
# Audio Utilities
# ============================================================


def save_wav_16k_mono(samples_float32, output_path: Path):
    """Write float32 [-1, 1] samples as 16kHz mono 16-bit PCM WAV."""
    import numpy as np

    samples = np.clip(samples_float32, -1.0, 1.0)
    int16_data = (samples * 32767).astype(np.int16)

    with wave.open(str(output_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(int16_data.tobytes())


def resample_to_16k_mono(audio_array, orig_sr: int):
    """Resample audio to 16kHz mono using scipy."""
    import numpy as np

    audio = np.asarray(audio_array, dtype=np.float32)

    # Convert to mono if multi-channel
    if audio.ndim > 1:
        audio = audio.mean(axis=1)

    if orig_sr == SAMPLE_RATE:
        return audio

    from math import gcd

    from scipy.signal import resample_poly

    g = gcd(SAMPLE_RATE, orig_sr)
    up = SAMPLE_RATE // g
    down = orig_sr // g
    resampled = resample_poly(audio, up, down)
    return resampled.astype(np.float32)


def get_wav_duration(path: Path) -> float:
    """Get WAV file duration in seconds."""
    try:
        with wave.open(str(path), "rb") as wf:
            return wf.getnframes() / wf.getframerate()
    except Exception:
        return 0.0


def _extract_neutral_keywords(text: str, n: int = 2) -> list[str]:
    """Extract short content words from Chinese text for contains_all matching.

    Picks 2-character substrings that are common to simplified and traditional
    Chinese, avoiding single-character function words. This is used for
    MINDS-14 conversational data where speakers may have accents causing
    Qwen3-ASR to output traditional characters.
    """
    import re

    # Remove punctuation and whitespace
    cleaned = re.sub(r"[^\u4e00-\u9fff]", "", text)

    # Extract all 2-character substrings as candidate keywords
    candidates = []
    for i in range(0, len(cleaned) - 1):
        bigram = cleaned[i : i + 2]
        candidates.append(bigram)

    if not candidates:
        return [cleaned[:2]] if len(cleaned) >= 2 else [cleaned]

    # Pick n keywords spread across the text
    if len(candidates) <= n:
        return candidates

    step = len(candidates) // n
    result = []
    for i in range(n):
        result.append(candidates[i * step])
    return result


def _extract_codeswitching_keywords(text: str, n: int = 4) -> list[str]:
    """Extract keywords from mixed zh-en text for contains_all matching.

    English words (3+ chars) are used directly as keywords.
    Chinese segments use bigram extraction like _extract_neutral_keywords.
    """
    import re

    segments = re.findall(r"[a-zA-Z]+|[\u4e00-\u9fff]+", text)
    en_keywords = [s for s in segments if s.isascii() and len(s) >= 3]
    zh_segments = [s for s in segments if not s.isascii()]

    # Filter out common filler words and noise markers
    en_stopwords = {"UNK", "unk", "and", "the", "but", "for", "not", "you", "are"}
    en_keywords = [w for w in en_keywords if w not in en_stopwords]

    # Extract Chinese bigrams
    zh_bigrams: list[str] = []
    for seg in zh_segments:
        for i in range(len(seg) - 1):
            zh_bigrams.append(seg[i : i + 2])

    # Combine: prefer English words first, fill with Chinese bigrams
    result: list[str] = []
    # Take up to 2 English keywords spread across
    if en_keywords:
        step = max(1, len(en_keywords) // 2)
        for i in range(0, len(en_keywords), step):
            if len(result) < 2:
                result.append(en_keywords[i])
    # Fill remaining with Chinese bigrams
    remaining = n - len(result)
    if zh_bigrams and remaining > 0:
        step = max(1, len(zh_bigrams) // remaining)
        for i in range(0, len(zh_bigrams), step):
            if len(result) < n:
                result.append(zh_bigrams[i])

    return result[:n]


# ============================================================
# AISHELL-1 Download
# ============================================================


def download_aishell_samples(n_samples: int = 8) -> list[dict]:
    """Download n_samples from AISHELL-1 test split via HuggingFace."""
    try:
        from datasets import Audio, load_dataset
    except ImportError:
        print(
            "  [AISHELL] 跳过: 需要 `datasets` 库。"
            " 运行: uv run --with 'datasets[audio]' --with soundfile --with scipy ...",
            file=sys.stderr,
        )
        return []

    import numpy as np

    aishell_dir = REAL_AUDIO_DIR / "aishell"
    aishell_dir.mkdir(parents=True, exist_ok=True)

    # Try known AISHELL-1 dataset IDs
    dataset_ids = [
        ("carlot/AIShell", None),
    ]

    ds = None
    used_id = None
    for ds_id, ds_config in dataset_ids:
        try:
            print(f"  [AISHELL] 尝试加载 {ds_id} ...")
            kwargs = {
                "path": ds_id,
                "split": "test",
                "streaming": True,
            }
            if ds_config:
                kwargs["name"] = ds_config
            ds = load_dataset(**kwargs)
            ds = ds.cast_column("audio", Audio(sampling_rate=SAMPLE_RATE))
            used_id = ds_id
            print(f"  [AISHELL] 成功连接 {ds_id}")
            break
        except Exception as e:
            print(f"  [AISHELL] {ds_id} 不可用: {e}", file=sys.stderr)
            continue

    if ds is None:
        print("  [AISHELL] 所有数据源均不可用，跳过", file=sys.stderr)
        return []

    entries = []
    count = 0
    try:
        for example in ds:
            if count >= n_samples:
                break

            audio = example.get("audio")
            # AISHELL uses 'transcription' field with space-separated chars
            text = (
                example.get("transcription")
                or example.get("text")
                or example.get("transcript")
                or ""
            )

            if not audio or not text:
                continue

            # Clean text: AISHELL transcripts have space-separated chars
            text = text.replace(" ", "").strip()
            if not text:
                continue

            samples = np.asarray(audio["array"], dtype=np.float32)
            sr = audio["sampling_rate"]
            if sr != SAMPLE_RATE:
                samples = resample_to_16k_mono(samples, sr)

            entry_id = f"aishell_test_{count + 1:03d}"
            wav_path = aishell_dir / f"{entry_id}.wav"
            save_wav_16k_mono(samples, wav_path)

            duration = get_wav_duration(wav_path)
            print(f"  [AISHELL] {entry_id}: '{text[:40]}' ({duration:.1f}s)")

            entries.append(
                {
                    "id": entry_id,
                    "category": "recorded_aishell",
                    "expected_text": text,
                    "match_mode": "character_error_rate",
                    "audio_files": {"recorded": f"audio/recorded/aishell/{entry_id}.wav"},
                    "duration_sec": round(duration, 2),
                    "language": "zh",
                    "match_threshold": 0.15,
                }
            )
            count += 1
    except Exception as e:
        print(f"  [AISHELL] 下载中断 ({count} samples collected): {e}", file=sys.stderr)

    print(f"  [AISHELL] 共获取 {len(entries)} 条 (from {used_id})")
    return entries


# ============================================================
# Conversational Mandarin Download (MINDS-14 / Common Voice)
# ============================================================


def download_conversational_samples(n_samples: int = 5) -> list[dict]:
    """Download n_samples of conversational Mandarin from MINDS-14 or Common Voice."""
    try:
        from datasets import Audio, load_dataset
    except ImportError:
        print(
            "  [Conversational] 跳过: 需要 `datasets` 库。",
            file=sys.stderr,
        )
        return []

    import numpy as np

    conv_dir = REAL_AUDIO_DIR / "minds14"
    conv_dir.mkdir(parents=True, exist_ok=True)

    # MINDS-14 is publicly available with real Chinese conversational recordings
    dataset_ids = [
        ("PolyAI/minds14", "zh-CN", "train", "transcription"),
    ]

    ds = None
    used_id = None
    text_field = "transcription"
    for ds_id, lang_config, split, tf in dataset_ids:
        try:
            label = f"{ds_id}/{lang_config}"
            print(f"  [Conversational] 尝试加载 {label} ...")
            ds = load_dataset(
                ds_id,
                lang_config,
                split=split,
                streaming=True,
            )
            ds = ds.cast_column("audio", Audio(sampling_rate=SAMPLE_RATE))
            used_id = label
            text_field = tf
            print(f"  [Conversational] 成功连接 {label}")
            break
        except Exception as e:
            print(f"  [Conversational] {ds_id} 不可用: {e}", file=sys.stderr)
            continue

    if ds is None:
        print("  [Conversational] 所有数据源均不可用，跳过", file=sys.stderr)
        return []

    entries = []
    count = 0
    try:
        for example in ds:
            if count >= n_samples:
                break

            audio = example.get("audio")
            text = example.get(text_field, "")
            text = text.replace(" ", "").strip()

            if not audio or not text or len(text) < 2:
                continue

            samples = np.asarray(audio["array"], dtype=np.float32)
            sr = audio["sampling_rate"]
            if sr != SAMPLE_RATE:
                samples = resample_to_16k_mono(samples, sr)

            entry_id = f"conv_zh_{count + 1:03d}"
            wav_path = conv_dir / f"{entry_id}.wav"
            save_wav_16k_mono(samples, wav_path)

            duration = get_wav_duration(wav_path)
            print(f"  [Conversational] {entry_id}: '{text[:40]}' ({duration:.1f}s)")

            # Extract 2 keywords from the text for contains_all matching.
            # MINDS-14 speakers may have accents causing ASR to output
            # traditional Chinese, so use short content words that are
            # identical in simplified and traditional Chinese.
            keywords = _extract_neutral_keywords(text, n=2)

            entries.append(
                {
                    "id": entry_id,
                    "category": "recorded_minds14",
                    "expected_text": text,
                    "match_mode": "contains_all",
                    "audio_files": {"recorded": f"audio/recorded/minds14/{entry_id}.wav"},
                    "duration_sec": round(duration, 2),
                    "language": "zh",
                    "match_keywords": keywords,
                }
            )
            count += 1
    except Exception as e:
        print(
            f"  [Conversational] 下载中断 ({count} samples collected): {e}",
            file=sys.stderr,
        )

    print(f"  [Conversational] 共获取 {len(entries)} 条 (from {used_id})")
    return entries


# ============================================================
# ASCEND Code-Switching Download
# ============================================================


def download_ascend_samples(n_samples: int = 10) -> list[dict]:
    """Download n_samples of code-switching from ASCEND test split."""
    try:
        from datasets import Audio, load_dataset
    except ImportError:
        print(
            "  [ASCEND] 跳过: 需要 `datasets` 库。",
            file=sys.stderr,
        )
        return []

    import numpy as np

    ascend_dir = REAL_AUDIO_DIR / "ascend"
    ascend_dir.mkdir(parents=True, exist_ok=True)

    try:
        print("  [ASCEND] 加载 CAiRE/ASCEND test split ...")
        ds = load_dataset("CAiRE/ASCEND", split="test", streaming=True)
        ds = ds.cast_column("audio", Audio(sampling_rate=SAMPLE_RATE))
        print("  [ASCEND] 成功连接")
    except Exception as e:
        print(f"  [ASCEND] 数据集不可用: {e}", file=sys.stderr)
        return []

    entries = []
    count = 0
    try:
        for example in ds:
            if count >= n_samples:
                break

            # Only mixed (code-switching) samples
            if example.get("language") != "mixed":
                continue

            audio = example.get("audio")
            text = example.get("transcription", "").strip()

            if not audio or not text:
                continue

            # Check duration (3-15 seconds)
            samples = np.asarray(audio["array"], dtype=np.float32)
            sr = audio["sampling_rate"]
            duration = len(samples) / sr
            if duration < 3.0 or duration > 15.0:
                continue

            # Ensure text contains actual English content and no noise markers
            import re

            if not re.search(r"[a-zA-Z]{3,}", text):
                continue
            if "[UNK]" in text or "[unk]" in text:
                continue

            if sr != SAMPLE_RATE:
                samples = resample_to_16k_mono(samples, sr)

            entry_id = f"ascend_cs_{count + 1:03d}"
            wav_path = ascend_dir / f"{entry_id}.wav"
            save_wav_16k_mono(samples, wav_path)

            duration = get_wav_duration(wav_path)
            keywords = _extract_codeswitching_keywords(text, n=4)
            print(f"  [ASCEND] {entry_id}: '{text[:50]}' ({duration:.1f}s)")

            entries.append(
                {
                    "id": entry_id,
                    "category": "recorded_ascend",
                    "expected_text": text,
                    "match_mode": "contains_all",
                    "audio_files": {"recorded": f"audio/recorded/ascend/{entry_id}.wav"},
                    "duration_sec": round(duration, 2),
                    "language": "mixed",
                    "match_keywords": keywords,
                }
            )
            count += 1
    except Exception as e:
        print(
            f"  [ASCEND] 下载中断 ({count} samples collected): {e}",
            file=sys.stderr,
        )

    print(f"  [ASCEND] 共获取 {len(entries)} 条 code-switching 音频")
    return entries


# ============================================================
# WenetSpeech Download
# ============================================================


def download_wenetspeech_samples(n_samples: int = 10) -> list[dict]:
    """Download n_samples from WenetSpeech TEST_NET split.

    WenetSpeech on HuggingFace uses Lhotse WebDataset format (jsonl.gz + tar.gz).
    We download the first tar.gz shard of TEST_NET and extract WAV files directly.
    """
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print(
            "  [WenetSpeech] 跳过: 需要 `huggingface_hub` 库。",
            file=sys.stderr,
        )
        return []

    import gzip
    import io
    import tarfile

    import numpy as np

    wenet_dir = REAL_AUDIO_DIR / "wenetspeech"
    wenet_dir.mkdir(parents=True, exist_ok=True)

    repo_id = "wenet-e2e/WenetSpeech"

    # Step 1: Download and parse the manifest (jsonl.gz) to get text labels
    try:
        print("  [WenetSpeech] 下载 TEST_NET manifest ...")
        manifest_path = hf_hub_download(
            repo_id=repo_id,
            filename="data/cuts_TEST_NET.00000000.jsonl.gz",
            repo_type="dataset",
        )
    except Exception as e:
        err_msg = str(e).lower()
        if "gated" in err_msg or "authorization" in err_msg or "401" in err_msg or "authenticated" in err_msg:
            print(
                "  [WenetSpeech] 需要 HuggingFace 授权。\n"
                "  请先访问 https://huggingface.co/datasets/wenet-e2e/WenetSpeech 申请访问权限，\n"
                "  然后运行 huggingface-cli login 登录。\n"
                "  使用 --skip-wenetspeech 跳过此数据集。",
                file=sys.stderr,
            )
        else:
            print(f"  [WenetSpeech] 数据集不可用: {e}", file=sys.stderr)
        return []

    # Parse manifest: each line is a JSON object with supervisions[0].text
    cuts_meta: dict[str, dict] = {}
    try:
        with gzip.open(manifest_path, "rt", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                cut = json.loads(line)
                cut_id = cut.get("id", "")
                sups = cut.get("supervisions", [])
                text = sups[0].get("text", "") if sups else ""
                duration = cut.get("duration", 0)
                rec = cut.get("recording", {})
                sources = rec.get("sources", [])
                wav_name = ""
                if sources:
                    # e.g. "data/cuts_TEST_NET.00000000/TEST_NET/TEST_NET_T0000000123_S00000.wav"
                    src_path = sources[0].get("source", "")
                    wav_name = src_path.rsplit("/", 1)[-1] if "/" in src_path else src_path

                text = text.replace(" ", "").strip()
                if text and len(text) >= 5 and 3.0 <= duration <= 15.0 and wav_name:
                    cuts_meta[wav_name] = {
                        "text": text,
                        "duration": duration,
                        "id": cut_id,
                    }
        print(f"  [WenetSpeech] manifest 中符合条件的条目: {len(cuts_meta)}")
    except Exception as e:
        print(f"  [WenetSpeech] manifest 解析失败: {e}", file=sys.stderr)
        return []

    if not cuts_meta:
        print("  [WenetSpeech] manifest 中无符合条件的条目", file=sys.stderr)
        return []

    # Step 2: Download and extract audio from tar.gz
    try:
        print("  [WenetSpeech] 下载 TEST_NET 音频 (shard 0) ...")
        tar_path = hf_hub_download(
            repo_id=repo_id,
            filename="data/cuts_TEST_NET.00000000.tar.gz",
            repo_type="dataset",
        )
    except Exception as e:
        print(f"  [WenetSpeech] 音频下载失败: {e}", file=sys.stderr)
        return []

    entries = []
    count = 0
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            for member in tar:
                if count >= n_samples:
                    break
                if not member.isfile() or not member.name.endswith(".wav"):
                    continue

                basename = member.name.rsplit("/", 1)[-1]
                if basename not in cuts_meta:
                    continue

                meta = cuts_meta[basename]
                text = meta["text"]

                f = tar.extractfile(member)
                if f is None:
                    continue

                wav_data = f.read()

                # Parse WAV and convert to 16kHz mono float32
                try:
                    import soundfile as sf

                    audio_array, sr = sf.read(io.BytesIO(wav_data), dtype="float32")
                    if audio_array.ndim > 1:
                        audio_array = audio_array.mean(axis=1)
                    if sr != SAMPLE_RATE:
                        audio_array = resample_to_16k_mono(audio_array, sr)
                except Exception:
                    continue

                entry_id = f"wenet_net_{count + 1:03d}"
                wav_out = wenet_dir / f"{entry_id}.wav"
                save_wav_16k_mono(audio_array, wav_out)

                duration = get_wav_duration(wav_out)
                print(f"  [WenetSpeech] {entry_id}: '{text[:50]}' ({duration:.1f}s)")

                entries.append(
                    {
                        "id": entry_id,
                        "category": "recorded_wenetspeech",
                        "expected_text": text,
                        "match_mode": "character_error_rate",
                        "audio_files": {
                            "recorded": f"audio/recorded/wenetspeech/{entry_id}.wav"
                        },
                        "duration_sec": round(duration, 2),
                        "language": "zh",
                        "match_threshold": 0.20,
                    }
                )
                count += 1
    except Exception as e:
        print(
            f"  [WenetSpeech] 提取中断 ({count} samples collected): {e}",
            file=sys.stderr,
        )

    print(f"  [WenetSpeech] 共获取 {len(entries)} 条多场景音频")
    return entries


# ============================================================
# Manifest Builder
# ============================================================


def build_manifest(all_entries: list[dict]) -> dict:
    """Build recorded_manifest.json structure."""
    return {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sample_rate": SAMPLE_RATE,
        "format": "16-bit PCM WAV, mono",
        "entries": all_entries,
    }


# ============================================================
# Main
# ============================================================


def main():
    parser = argparse.ArgumentParser(description="下载真实录音 ASR 测试数据")
    parser.add_argument(
        "--n-aishell",
        type=int,
        default=8,
        help="AISHELL-1 样本数 (default: 8)",
    )
    parser.add_argument(
        "--n-conversational",
        type=int,
        default=5,
        help="MINDS-14 样本数 (default: 5)",
    )
    parser.add_argument(
        "--n-ascend",
        type=int,
        default=10,
        help="ASCEND code-switching 样本数 (default: 10)",
    )
    parser.add_argument(
        "--n-wenetspeech",
        type=int,
        default=10,
        help="WenetSpeech 样本数 (default: 10)",
    )
    parser.add_argument(
        "--skip-wenetspeech",
        action="store_true",
        help="跳过 WenetSpeech（需要 HuggingFace 授权的 gated 数据集）",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("Recorded ASR Test Data Downloader")
    print("=" * 60)

    REAL_AUDIO_DIR.mkdir(parents=True, exist_ok=True)

    all_entries: list[dict] = []

    # 1. AISHELL-1
    print("\n[1/4] AISHELL-1 (标准普通话)")
    aishell_entries = download_aishell_samples(args.n_aishell)
    all_entries.extend(aishell_entries)

    # 2. MINDS-14
    print("\n[2/4] MINDS-14 (真实对话录音)")
    cv_entries = download_conversational_samples(args.n_conversational)
    all_entries.extend(cv_entries)

    # 3. ASCEND Code-Switching
    print("\n[3/4] ASCEND Code-Switching (真实中英混合对话)")
    ascend_entries = download_ascend_samples(args.n_ascend)
    all_entries.extend(ascend_entries)

    # 4. WenetSpeech
    if not args.skip_wenetspeech:
        print("\n[4/4] WenetSpeech TEST_NET (多场景中文)")
        wenet_entries = download_wenetspeech_samples(args.n_wenetspeech)
        all_entries.extend(wenet_entries)
    else:
        print("\n[4/4] WenetSpeech — 跳过 (--skip-wenetspeech)")

    # Write manifest
    manifest = build_manifest(all_entries)
    manifest_path = FIXTURES_DIR / "recorded_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    # Summary
    print(f"\n{'=' * 60}")
    print("下载完成!")
    print(f"  recorded_manifest.json: {manifest_path}")
    print(f"  条目总数: {len(all_entries)}")

    categories: dict[str, int] = {}
    for e in all_entries:
        cat = e["category"]
        categories[cat] = categories.get(cat, 0) + 1

    print("\n  分类统计:")
    for cat, count in sorted(categories.items()):
        print(f"    {cat}: {count}")

    total_duration = sum(e["duration_sec"] for e in all_entries)
    print(f"\n  总时长: {total_duration:.1f}s")


if __name__ == "__main__":
    main()
