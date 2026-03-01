#!/usr/bin/env python3
"""
ASR 引擎量化对比评估脚本

对比 4 个引擎：
  1. Streaming Paraformer（流式 NAR）
  2. Qwen3-ASR 离线（全量音频一次推理）
  3. Qwen3-ASR 流式（chunk + rollback 模拟流式）
  4. SenseVoice Nano（离线 + VAD）

使用项目已有测试语料（corpus.json + real_manifest.json），
计算逐条 CER 并输出 Markdown 报告。

用法：
    uv run --with sherpa-onnx python3 scripts/benchmark_engines.py
    uv run --with sherpa-onnx python3 scripts/benchmark_engines.py --output docs/benchmark-report.md
"""

import argparse
import ctypes
import json
import os
import re
import struct
import time
import wave
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

# ============================================================================
# 路径常量
# ============================================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = PROJECT_ROOT / "tests" / "fixtures"
CORPUS_JSON = FIXTURES_DIR / "corpus.json"
REAL_MANIFEST_JSON = FIXTURES_DIR / "real_manifest.json"

MODELS_DIR = Path.home() / "Library" / "Application Support" / "Nano Typeless" / "models"
QWEN_MODEL_DIR = MODELS_DIR / "Qwen3-ASR-0.6B"
PARAFORMER_MODEL_DIR = MODELS_DIR / "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
SENSEVOICE_MODEL_DIR = MODELS_DIR / "sherpa-onnx-sense-voice-funasr-nano-int8-2025-12-17"
ITN_FST_PATH = MODELS_DIR / "itn_zh_number.fst"

QWEN_DYLIB = PROJECT_ROOT / "Frameworks" / "qwen-asr" / "lib" / "libqwen_asr.dylib"

# ============================================================================
# WAV 加载
# ============================================================================

def load_wav_as_float32(wav_path: str) -> tuple[list[float], int]:
    """加载 WAV 文件为 float32 PCM 样本 + 采样率"""
    with wave.open(wav_path, "rb") as wf:
        sample_rate = wf.getframerate()
        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sample_width == 2:
        fmt = f"<{n_frames * n_channels}h"
        int_samples = struct.unpack(fmt, raw)
        samples = [s / 32768.0 for s in int_samples]
    elif sample_width == 4:
        fmt = f"<{n_frames * n_channels}f"
        samples = list(struct.unpack(fmt, raw))
    else:
        raise ValueError(f"Unsupported sample width: {sample_width}")

    if n_channels == 2:
        samples = samples[::2]

    return samples, sample_rate


# ============================================================================
# CER 计算
# ============================================================================

ZH_PUNCT = "\uff0c\u3002\uff01\uff1f\u3001\uff1b\uff1a\u201c\u201d\u2018\u2019\uff08\uff09\u3010\u3011\u300a\u300b"
EN_PUNCT = ",.!?;:'\"()[]<>"
MISC_PUNCT = "\u2026\u2014\u2013\u00b7"
ALL_PUNCT = set(ZH_PUNCT + EN_PUNCT + MISC_PUNCT)


def normalize_text(text: str) -> str:
    result = "".join(ch for ch in text if ch not in ALL_PUNCT)
    result = result.lower()
    result = "".join(result.split())
    return result


def levenshtein_distance(a: str, b: str) -> int:
    m, n = len(a), len(b)
    if m == 0: return n
    if n == 0: return m
    prev = list(range(n + 1))
    curr = [0] * (n + 1)
    for i in range(1, m + 1):
        curr[0] = i
        for j in range(1, n + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        prev, curr = curr, prev
    return prev[n]


def compute_cer(actual: str, expected: str) -> float:
    na = normalize_text(actual)
    ne = normalize_text(expected)
    if not ne:
        return 0.0 if not na else 1.0
    return levenshtein_distance(na, ne) / len(ne)


# ============================================================================
# 引擎封装
# ============================================================================

class QwenASROfflineEngine:
    """Qwen3-ASR 离线模式：一次性传入全部音频"""
    NAME = "Qwen3-ASR (离线)"
    SHORT = "qwen_offline"

    def __init__(self, model_dir: str, dylib_path: str):
        self.lib = ctypes.CDLL(dylib_path)
        self._setup(self.lib)
        self.engine = self.lib.qwen_asr_load_model(model_dir.encode(), 4, 0)
        if not self.engine:
            raise RuntimeError(f"Failed to load Qwen3-ASR from {model_dir}")
        self.lib.qwen_asr_set_language(self.engine, b"chinese")

    @staticmethod
    def _setup(lib):
        lib.qwen_asr_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
        lib.qwen_asr_load_model.restype = ctypes.c_void_p
        lib.qwen_asr_free.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_free.restype = None
        lib.qwen_asr_set_language.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.qwen_asr_set_language.restype = ctypes.c_int32
        lib.qwen_asr_transcribe_pcm.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_float), ctypes.c_int32]
        lib.qwen_asr_transcribe_pcm.restype = ctypes.c_void_p
        lib.qwen_asr_free_string.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_free_string.restype = None

    def transcribe(self, samples: list[float]) -> str:
        arr = (ctypes.c_float * len(samples))(*samples)
        ptr = self.lib.qwen_asr_transcribe_pcm(self.engine, arr, len(samples))
        if not ptr: return ""
        text = ctypes.string_at(ptr).decode("utf-8")
        self.lib.qwen_asr_free_string(ptr)
        return text

    def close(self):
        if self.engine:
            self.lib.qwen_asr_free(self.engine)
            self.engine = None


class QwenASRStreamEngine:
    """Qwen3-ASR 流式模式：chunk + rollback"""
    NAME = "Qwen3-ASR (流式)"
    SHORT = "qwen_stream"

    def __init__(self, model_dir: str, dylib_path: str):
        self.lib = ctypes.CDLL(dylib_path)
        self._setup(self.lib)
        self.engine = self.lib.qwen_asr_load_model(model_dir.encode(), 4, 0)
        if not self.engine:
            raise RuntimeError(f"Failed to load Qwen3-ASR from {model_dir}")
        self.lib.qwen_asr_set_language(self.engine, b"chinese")
        # 与 app 中一致的流式参数
        self.lib.qwen_asr_stream_set_chunk_sec(self.engine, ctypes.c_float(2.0))
        self.lib.qwen_asr_stream_set_rollback(self.engine, 3)
        self.lib.qwen_asr_stream_set_unfixed_chunks(self.engine, 1)
        self.lib.qwen_asr_stream_set_max_new_tokens(self.engine, 32)

    @staticmethod
    def _setup(lib):
        lib.qwen_asr_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
        lib.qwen_asr_load_model.restype = ctypes.c_void_p
        lib.qwen_asr_free.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_free.restype = None
        lib.qwen_asr_set_language.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.qwen_asr_set_language.restype = ctypes.c_int32
        lib.qwen_asr_stream_set_chunk_sec.argtypes = [ctypes.c_void_p, ctypes.c_float]
        lib.qwen_asr_stream_set_chunk_sec.restype = None
        lib.qwen_asr_stream_set_rollback.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        lib.qwen_asr_stream_set_rollback.restype = None
        lib.qwen_asr_stream_set_unfixed_chunks.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        lib.qwen_asr_stream_set_unfixed_chunks.restype = None
        lib.qwen_asr_stream_set_max_new_tokens.argtypes = [ctypes.c_void_p, ctypes.c_int32]
        lib.qwen_asr_stream_set_max_new_tokens.restype = None
        lib.qwen_asr_stream_new.argtypes = []
        lib.qwen_asr_stream_new.restype = ctypes.c_void_p
        lib.qwen_asr_stream_free.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_stream_free.restype = None
        lib.qwen_asr_stream_reset.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_stream_reset.restype = None
        lib.qwen_asr_stream_push.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_float), ctypes.c_int32, ctypes.c_int32]
        lib.qwen_asr_stream_push.restype = ctypes.c_void_p
        lib.qwen_asr_stream_get_result.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_stream_get_result.restype = ctypes.c_void_p
        lib.qwen_asr_free_string.argtypes = [ctypes.c_void_p]
        lib.qwen_asr_free_string.restype = None

    def transcribe(self, samples: list[float]) -> str:
        state = self.lib.qwen_asr_stream_new()
        if not state: return ""

        # 模拟真实录音：每 4096 样本（0.256s @16kHz）推送一次
        chunk_size = 4096
        for i in range(0, len(samples), chunk_size):
            chunk = samples[i:i+chunk_size]
            arr = (ctypes.c_float * len(chunk))(*chunk)
            ptr = self.lib.qwen_asr_stream_push(self.engine, state, arr, len(chunk), 0)
            if ptr:
                self.lib.qwen_asr_free_string(ptr)

        # finalize
        empty = (ctypes.c_float * 0)()
        ptr = self.lib.qwen_asr_stream_push(self.engine, state, empty, 0, 1)
        if ptr:
            self.lib.qwen_asr_free_string(ptr)

        # 获取完整结果
        res_ptr = self.lib.qwen_asr_stream_get_result(state)
        text = ""
        if res_ptr:
            text = ctypes.string_at(res_ptr).decode("utf-8")
            self.lib.qwen_asr_free_string(res_ptr)

        self.lib.qwen_asr_stream_free(state)
        return text

    def close(self):
        if self.engine:
            self.lib.qwen_asr_free(self.engine)
            self.engine = None


class ParaformerEngine:
    """Streaming Paraformer（sherpa-onnx 流式）"""
    NAME = "Streaming Paraformer"
    SHORT = "paraformer"

    def __init__(self, model_dir: str, itn_fst_path: Optional[str] = None):
        import sherpa_onnx
        encoder = os.path.join(model_dir, "encoder.int8.onnx")
        decoder = os.path.join(model_dir, "decoder.int8.onnx")
        tokens = os.path.join(model_dir, "tokens.txt")
        if not os.path.exists(encoder):
            encoder = os.path.join(model_dir, "encoder.onnx")
        if not os.path.exists(decoder):
            decoder = os.path.join(model_dir, "decoder.onnx")

        self.recognizer = sherpa_onnx.OnlineRecognizer.from_paraformer(
            tokens=tokens, encoder=encoder, decoder=decoder,
            num_threads=2, sample_rate=16000, feature_dim=80,
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.4, rule2_min_trailing_silence=1.2,
            rule3_min_utterance_length=20, decoding_method="greedy_search",
            provider="cpu", rule_fsts=itn_fst_path or "",
        )

    def transcribe(self, samples: list[float]) -> str:
        stream = self.recognizer.create_stream()
        chunk_size = 4096
        for i in range(0, len(samples), chunk_size):
            stream.accept_waveform(16000, samples[i:i+chunk_size])
        stream.accept_waveform(16000, [0.0] * 4800)
        while self.recognizer.is_ready(stream):
            self.recognizer.decode_stream(stream)
        text = self.recognizer.get_result(stream)
        text = re.sub(r"([\u4e00-\u9fa5])\s+([a-zA-Z0-9])", r"\1\2", text)
        text = re.sub(r"([a-zA-Z0-9])\s+([\u4e00-\u9fa5])", r"\1\2", text)
        return text.strip()

    def close(self):
        pass


class SenseVoiceEngine:
    """SenseVoice Nano（sherpa-onnx 离线）"""
    NAME = "SenseVoice Nano"
    SHORT = "sensevoice"

    def __init__(self, model_dir: str):
        import sherpa_onnx
        model = os.path.join(model_dir, "model.int8.onnx")
        tokens = os.path.join(model_dir, "tokens.txt")
        if not os.path.exists(model):
            model = os.path.join(model_dir, "model.onnx")

        self.recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=model, tokens=tokens,
            num_threads=2, sample_rate=16000, feature_dim=80,
            use_itn=True, language="auto",
        )

    def transcribe(self, samples: list[float]) -> str:
        stream = self.recognizer.create_stream()
        stream.accept_waveform(16000, samples)
        self.recognizer.decode_stream(stream)
        text = stream.result.text
        text = re.sub(r"([\u4e00-\u9fa5])\s+([a-zA-Z0-9])", r"\1\2", text)
        text = re.sub(r"([a-zA-Z0-9])\s+([\u4e00-\u9fa5])", r"\1\2", text)
        return text.strip()

    def close(self):
        pass


# ============================================================================
# 数据结构
# ============================================================================

@dataclass
class Entry:
    id: str
    category: str
    expected_text: str
    audio_path: str
    language: str
    duration_sec: float

@dataclass
class Result:
    entry: Entry
    engine_name: str
    output_text: str
    cer: float
    elapsed_sec: float


def load_entries() -> list[Entry]:
    entries = []
    for path in [CORPUS_JSON, REAL_MANIFEST_JSON]:
        if not path.exists():
            print(f"  [WARN] {path} not found, skipping")
            continue
        with open(path) as f:
            data = json.load(f)
        for item in data["entries"]:
            if item.get("match_mode") == "empty_or_whitespace":
                continue
            if not item.get("expected_text", "").strip() and not item.get("text_input", "").strip():
                continue
            audio_files = item.get("audio_files", {})
            audio_path = None
            for key in ["edge_tts", "real", "synthetic"]:
                if key in audio_files:
                    candidate = FIXTURES_DIR / audio_files[key]
                    if candidate.exists():
                        audio_path = str(candidate)
                        break
            if not audio_path:
                continue
            # 优先用 text_input 作为参考文本（完整文本），expected_text 可能只是关键词
            ref_text = item.get("text_input", "").strip() or item.get("expected_text", "").strip()
            entries.append(Entry(
                id=item["id"], category=item.get("category", "unknown"),
                expected_text=ref_text, audio_path=audio_path,
                language=item.get("language", "zh"), duration_sec=item.get("duration_sec", 0),
            ))
    return entries


# ============================================================================
# 评估与报告生成
# ============================================================================

def run_engine(engine, engine_name: str, entries: list[Entry]) -> list[Result]:
    results = []
    for i, e in enumerate(entries):
        samples, _ = load_wav_as_float32(e.audio_path)
        t0 = time.monotonic()
        output = engine.transcribe(samples)
        elapsed = time.monotonic() - t0
        cer = compute_cer(output, e.expected_text)
        results.append(Result(entry=e, engine_name=engine_name, output_text=output, cer=cer, elapsed_sec=elapsed))
        tag = "OK" if cer <= 0.15 else ("WARN" if cer <= 0.30 else "HIGH")
        print(f"  [{i+1:3d}/{len(entries)}] [{tag:4s}] CER={cer:.3f} | {e.id}")
    return results


def generate_report(
    all_results: dict[str, list[Result]],
    entries: list[Entry],
    output_path: Optional[str],
):
    lines: list[str] = []

    def w(s=""):
        lines.append(s)

    engine_names = list(all_results.keys())
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    w(f"# ASR 引擎量化对比评估报告")
    w()
    w(f"*生成时间：{timestamp}*")
    w(f"*测试集：{len(entries)} 条音频（corpus.json + real_manifest.json）*")
    w(f"*引擎：{', '.join(engine_names)}*")
    w()
    w("---")
    w()

    # ---- 1. 总体汇总 ----
    w("## 1. 总体 CER 汇总")
    w()
    w("| 引擎 | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |")
    w("|------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|")
    total_audio = sum(e.duration_sec for e in entries)
    for name in engine_names:
        rs = all_results[name]
        avg_cer = sum(r.cer for r in rs) / len(rs)
        perfect = sum(1 for r in rs if r.cer < 0.001)
        low = sum(1 for r in rs if r.cer <= 0.10)
        mid = sum(1 for r in rs if r.cer <= 0.20)
        high = sum(1 for r in rs if r.cer > 0.20)
        total_t = sum(r.elapsed_sec for r in rs)
        rtf = total_t / total_audio if total_audio > 0 else 0
        w(f"| {name} | {avg_cer:.4f} | {perfect}/{len(rs)} | {low} | {mid} | {high} | {total_t:.1f}s | {rtf:.3f}x |")
    w()

    # ---- 2. 按类别汇总 ----
    w("## 2. 按数据集/类别的平均 CER")
    w()
    cats = sorted(set(e.category for e in entries))

    header = "| 类别 | N |"
    sep = "|------|:-:|"
    for name in engine_names:
        short = name.split("(")[0].strip()[:12]
        header += f" {short} |"
        sep += ":------:|"
    header += " 最佳引擎 |"
    sep += "---------|"
    w(header)
    w(sep)

    for cat in cats:
        cat_entries = [e for e in entries if e.category == cat]
        n = len(cat_entries)
        cat_ids = {e.id for e in cat_entries}
        avgs = {}
        for name in engine_names:
            cat_rs = [r for r in all_results[name] if r.entry.id in cat_ids]
            avgs[name] = sum(r.cer for r in cat_rs) / len(cat_rs) if cat_rs else 999
        best = min(avgs, key=avgs.get)
        row = f"| {cat} | {n} |"
        for name in engine_names:
            v = avgs[name]
            bold = "**" if name == best and v < 999 else ""
            row += f" {bold}{v:.3f}{bold} |"
        row += f" {best.split('(')[0].strip()} |"
        w(row)

    # Overall
    row = f"| **OVERALL** | {len(entries)} |"
    overall_avgs = {}
    for name in engine_names:
        rs = all_results[name]
        avg = sum(r.cer for r in rs) / len(rs)
        overall_avgs[name] = avg
    best = min(overall_avgs, key=overall_avgs.get)
    for name in engine_names:
        v = overall_avgs[name]
        bold = "**" if name == best else ""
        row += f" {bold}{v:.4f}{bold} |"
    row += f" **{best.split('(')[0].strip()}** |"
    w(row)
    w()

    # ---- 3. 逐条对比 ----
    w("## 3. 逐条 CER 对比")
    w()
    header = "| ID | 类别 |"
    sep = "|-----|------|"
    for name in engine_names:
        short = name.replace("Qwen3-ASR ", "Q").replace("Streaming ", "S.").replace("SenseVoice ", "SV ")[:10]
        header += f" {short} |"
        sep += ":-----:|"
    header += " 最佳 |"
    sep += "------|"
    w(header)
    w(sep)

    for e in entries:
        cers = {}
        for name in engine_names:
            r = next((r for r in all_results[name] if r.entry.id == e.id), None)
            cers[name] = r.cer if r else 999
        best_name = min(cers, key=cers.get)
        row = f"| {e.id} | {e.category} |"
        for name in engine_names:
            v = cers[name]
            if v < 0.001:
                cell = "**0**"
            elif v > 1.0:
                cell = f"{v:.1f}"
            else:
                cell = f"{v:.3f}"
            if name == best_name and v < 999:
                cell = f"**{cell.replace('**','')}**"
            row += f" {cell} |"
        row += f" {best_name.split('(')[0].strip()[:8]} |"
        w(row)
    w()

    # ---- 4. 推理速度 ----
    w("## 4. 推理速度对比")
    w()
    w("| 引擎 | 总音频 | 总推理 | RTF | 平均/条 |")
    w("|------|:-----:|:-----:|:---:|:------:|")
    for name in engine_names:
        rs = all_results[name]
        t_audio = sum(r.entry.duration_sec for r in rs)
        t_infer = sum(r.elapsed_sec for r in rs)
        rtf = t_infer / t_audio if t_audio > 0 else 0
        avg = t_infer / len(rs)
        w(f"| {name} | {t_audio:.0f}s | {t_infer:.1f}s | {rtf:.3f}x | {avg:.2f}s |")
    w()

    # ---- 5. 错误案例分析 ----
    w("## 5. 各引擎识别错误案例详细分析")
    w()
    CER_THRESHOLD = 0.05  # CER > 5% 视为不准确

    for name in engine_names:
        rs = all_results[name]
        errors = [r for r in rs if r.cer > CER_THRESHOLD]
        errors.sort(key=lambda r: -r.cer)

        w(f"### 5.{engine_names.index(name)+1} {name}（{len(errors)} 条不准确）")
        w()

        if not errors:
            w("所有条目 CER ≤ 0.05，无显著错误。")
            w()
            continue

        w("| # | ID | CER | 期望文本 | 识别结果 | 错误类型 |")
        w("|:-:|-----|:---:|---------|---------|---------|")

        for i, r in enumerate(errors):
            expected_norm = normalize_text(r.entry.expected_text)
            actual_norm = normalize_text(r.output_text)

            # 分析错误类型
            error_types = []
            # 繁体字检测
            if any('\u7e41' <= ch <= '\u9fa5' for ch in r.output_text):
                import unicodedata
                trad_chars = [ch for ch in r.output_text if unicodedata.name(ch, "").startswith("CJK") and ch != ch]
                # 简单检测：看是否有常见繁体字
                trad_indicators = set("書學數點機語認識經過國開會從發時問題這個應該進來說長給對門關電話東風車後飛運動員")
                found_trad = set(r.output_text) & trad_indicators
                if found_trad and not (set(r.entry.expected_text) & found_trad):
                    error_types.append("繁体字输出")

            # 英文词汇错误
            en_expected = set(re.findall(r"[a-zA-Z]+", r.entry.expected_text.lower()))
            en_actual = set(re.findall(r"[a-zA-Z]+", r.output_text.lower()))
            missed_en = en_expected - en_actual
            if missed_en:
                error_types.append(f"英文词丢失: {','.join(list(missed_en)[:3])}")

            # 数字格式差异
            if re.search(r"\d", r.entry.expected_text) or re.search(r"[一二三四五六七八九十百千万亿]", r.entry.expected_text):
                if r.cer > 0.1:
                    error_types.append("数字/量词")

            # 截断
            if len(actual_norm) < len(expected_norm) * 0.7:
                error_types.append("截断")
            elif len(actual_norm) > len(expected_norm) * 1.4:
                error_types.append("幻觉/冗余")

            # 同音字
            if not error_types and r.cer <= 0.3:
                error_types.append("同音字/近音字")

            if not error_types:
                error_types.append("综合误差")

            err_str = ", ".join(error_types)
            exp_short = r.entry.expected_text[:40] + ("…" if len(r.entry.expected_text) > 40 else "")
            out_short = r.output_text[:40] + ("…" if len(r.output_text) > 40 else "")
            cer_str = f"{r.cer:.3f}" if r.cer <= 1.0 else f"{r.cer:.1f}"
            w(f"| {i+1} | {r.entry.id} | {cer_str} | {exp_short} | {out_short} | {err_str} |")

        w()

    # ---- 6. 综合分析 ----
    w("## 6. 综合分析与建议")
    w()

    # 找每个类别的最佳引擎
    w("### 各场景最佳引擎推荐")
    w()
    w("| 场景 | 推荐引擎 | 理由 |")
    w("|------|---------|------|")

    cat_winners = {}
    for cat in cats:
        cat_ids = {e.id for e in entries if e.category == cat}
        avgs = {}
        for name in engine_names:
            cat_rs = [r for r in all_results[name] if r.entry.id in cat_ids]
            avgs[name] = sum(r.cer for r in cat_rs) / len(cat_rs) if cat_rs else 999
        best = min(avgs, key=avgs.get)
        cat_winners[cat] = (best, avgs[best])

    for cat, (best, cer) in sorted(cat_winners.items()):
        w(f"| {cat} | {best} | CER={cer:.3f} |")
    w()

    w("### 引擎特点总结")
    w()
    for name in engine_names:
        rs = all_results[name]
        avg = sum(r.cer for r in rs) / len(rs)
        perfect = sum(1 for r in rs if r.cer < 0.001)
        t_infer = sum(r.elapsed_sec for r in rs)
        rtf = t_infer / total_audio if total_audio > 0 else 0
        errors = sum(1 for r in rs if r.cer > CER_THRESHOLD)
        w(f"**{name}**")
        w(f"- 平均 CER: {avg:.4f}")
        w(f"- 完美识别 (CER=0): {perfect}/{len(rs)} 条")
        w(f"- 不准确 (CER>5%): {errors}/{len(rs)} 条")
        w(f"- RTF: {rtf:.3f}x")
        w()

    w("---")
    w()
    w(f"*报告由 `scripts/benchmark_engines.py` 自动生成*")

    report = "\n".join(lines)

    # 输出
    if output_path:
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(report)
        print(f"\n报告已保存到: {output_path}")
    else:
        print(report)

    return report


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="ASR 引擎量化对比评估")
    parser.add_argument("--output", "-o", type=str, default=None, help="输出 Markdown 报告路径")
    parser.add_argument("--engines", type=str, default="all",
                        help="要评估的引擎，逗号分隔：paraformer,qwen_offline,qwen_stream,sensevoice (默认 all)")
    args = parser.parse_args()

    if args.engines == "all":
        engine_list = ["paraformer", "qwen_offline", "qwen_stream", "sensevoice"]
    else:
        engine_list = [e.strip() for e in args.engines.split(",")]

    print("=" * 100)
    print("ASR 引擎量化对比评估")
    print("=" * 100)

    print("\n[1] 加载测试数据...")
    entries = load_entries()
    print(f"  共 {len(entries)} 条可评估条目")
    cats = {}
    for e in entries:
        cats.setdefault(e.category, 0)
        cats[e.category] += 1
    for cat, n in sorted(cats.items()):
        print(f"    {cat}: {n} 条")

    all_results: dict[str, list[Result]] = {}
    step = 2

    # Qwen3-ASR 离线
    if "qwen_offline" in engine_list:
        print(f"\n[{step}] 初始化 Qwen3-ASR (离线)...")
        step += 1
        if QWEN_DYLIB.exists() and QWEN_MODEL_DIR.exists():
            eng = QwenASROfflineEngine(str(QWEN_MODEL_DIR), str(QWEN_DYLIB))
            print(f"  加载成功，开始评估...")
            all_results[QwenASROfflineEngine.NAME] = run_engine(eng, QwenASROfflineEngine.NAME, entries)
            eng.close()
        else:
            print(f"  [SKIP] 模型或 dylib 不存在")

    # Qwen3-ASR 流式
    if "qwen_stream" in engine_list:
        print(f"\n[{step}] 初始化 Qwen3-ASR (流式)...")
        step += 1
        if QWEN_DYLIB.exists() and QWEN_MODEL_DIR.exists():
            eng = QwenASRStreamEngine(str(QWEN_MODEL_DIR), str(QWEN_DYLIB))
            print(f"  加载成功，开始评估...")
            all_results[QwenASRStreamEngine.NAME] = run_engine(eng, QwenASRStreamEngine.NAME, entries)
            eng.close()
        else:
            print(f"  [SKIP] 模型或 dylib 不存在")

    # Streaming Paraformer
    if "paraformer" in engine_list:
        print(f"\n[{step}] 初始化 Streaming Paraformer...")
        step += 1
        if PARAFORMER_MODEL_DIR.exists():
            itn = str(ITN_FST_PATH) if ITN_FST_PATH.exists() else None
            eng = ParaformerEngine(str(PARAFORMER_MODEL_DIR), itn)
            print(f"  加载成功 (ITN: {'on' if itn else 'off'})，开始评估...")
            all_results[ParaformerEngine.NAME] = run_engine(eng, ParaformerEngine.NAME, entries)
            eng.close()
        else:
            print(f"  [SKIP] 模型不存在")

    # SenseVoice Nano
    if "sensevoice" in engine_list:
        print(f"\n[{step}] 初始化 SenseVoice Nano...")
        step += 1
        if SENSEVOICE_MODEL_DIR.exists():
            eng = SenseVoiceEngine(str(SENSEVOICE_MODEL_DIR))
            print(f"  加载成功，开始评估...")
            all_results[SenseVoiceEngine.NAME] = run_engine(eng, SenseVoiceEngine.NAME, entries)
            eng.close()
        else:
            print(f"  [SKIP] 模型不存在")

    if not all_results:
        print("\n没有可用的引擎，退出。")
        return

    print(f"\n[{step}] 生成对比报告...")
    output = args.output or str(PROJECT_ROOT / "docs" / "benchmark-report.md")
    generate_report(all_results, entries, output)
    print("\n评估完成。")


if __name__ == "__main__":
    main()
