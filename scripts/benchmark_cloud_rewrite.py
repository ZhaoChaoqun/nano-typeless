#!/usr/bin/env python3
"""
Cloud Rewrite vs Local Rewrite 对比评估脚本

对比 3 个 Pipeline：
  1. Paraformer Pipeline（ASR + ITN → CSC → 标点）   — 基线
  2. Paraformer + Qwen3-0.6B LoRA Rewrite（本地）     — 现有方案
  3. Paraformer + SiliconFlow Qwen3-8B Cloud Rewrite  — 云端方案

使用与 benchmark_engines.py 相同测试语料和 CER 算法。

用法：
    # 需要设置环境变量 SILICONFLOW_API_KEY
    export SILICONFLOW_API_KEY="sk-xxx"

    uv run --with sherpa-onnx --with onnxruntime --with httpx \
        python3 scripts/benchmark_cloud_rewrite.py

    # 仅测试指定条目
    uv run --with sherpa-onnx --with onnxruntime --with httpx \
        python3 scripts/benchmark_cloud_rewrite.py --entry ascend_cs_003

    # 切换模型
    uv run --with sherpa-onnx --with onnxruntime --with httpx \
        python3 scripts/benchmark_cloud_rewrite.py --model Qwen/Qwen3-14B
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

import httpx

# ============================================================================
# 路径常量 (与 benchmark_engines.py 保持一致)
# ============================================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FIXTURES_DIR = PROJECT_ROOT / "tests" / "fixtures"
CORPUS_JSON = FIXTURES_DIR / "corpus.json"
REAL_MANIFEST_JSON = FIXTURES_DIR / "real_manifest.json"

MODELS_DIR = Path.home() / "Library" / "Application Support" / "Nano Typeless" / "models"
PARAFORMER_MODEL_DIR = MODELS_DIR / "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
ITN_FST_PATH = MODELS_DIR / "itn_zh_number.fst"
CSC_MODEL_DIR = MODELS_DIR / "macbert4csc-base-chinese"
PUNCT_MODEL_DIR = MODELS_DIR / "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"

QWEN3_REWRITE_DYLIB = PROJECT_ROOT / "Frameworks" / "qwen3-rewrite" / "lib" / "libqwen3_rewrite.dylib"
QWEN3_REWRITE_MODEL_DIR = Path.home() / "Github" / "Qwen3-0.6B" / "models" / "Qwen3-0.6B-rewrite-lora"

# ============================================================================
# Cloud Rewrite System Prompt (与本地 Rust 版 SYSTEM_PROMPT 完全一致)
# ============================================================================

SYSTEM_PROMPT = """你是一个文本格式化工具。将用户的口语化ASR语音文本转换为规范的书面文本。

规则：
1. 纠正同音错别字（如"油箱→邮箱"、"以经→已经"），去除口语赘词（如"那个"、"呃"）。
2. 根据语意添加标点符号，合理断句。
3. 数字格式化：日期、时间、金额、百分比转阿拉伯数字（三点半→3:30，百分之五→5%）。
4. 中文与英文/数字之间加一个空格。
5. 术语大小写：excel→Excel, chatgpt→ChatGPT, iphone→iPhone, cicd→CI/CD。
6. 保留英文原文：文本中的英文单词、短语必须原样保留，严禁翻译成中文（如"play basketball"保留，不改为"打篮球"；"variable"保留，不改为"变量"）。

重要约束：
- 只做格式修正，严禁改写句意、回答问题、翻译英文或添加/删除信息内容。
- 直接输出处理后的文本，无需任何解释。"""

# ============================================================================
# WAV 加载
# ============================================================================

def load_wav_as_float32(wav_path: str) -> tuple[list[float], int]:
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

    if n_channels > 1:
        samples = samples[::n_channels]
    return samples, sample_rate


# ============================================================================
# CER 计算 (与 benchmark_engines.py 完全一致)
# ============================================================================

def normalize_text(text: str) -> str:
    result = text.lower()
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


def compute_min_cer(actual: str, expected_texts: list[str]) -> float:
    """多候选 CER：取所有候选中的最小 CER"""
    if not expected_texts:
        return 1.0
    return min(compute_cer(actual, e) for e in expected_texts)


# ============================================================================
# 数据加载
# ============================================================================

@dataclass
class Entry:
    id: str
    category: str
    expected_texts: list[str]
    audio_path: str
    language: str
    duration_sec: float


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
            raw_expected = item.get("expected_text", "")
            if isinstance(raw_expected, list):
                expected_texts = [t for t in raw_expected if t.strip()]
            elif isinstance(raw_expected, str) and raw_expected.strip():
                expected_texts = [raw_expected]
            else:
                continue
            if not expected_texts:
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
            entries.append(Entry(
                id=item["id"], category=item.get("category", "unknown"),
                expected_texts=expected_texts, audio_path=audio_path,
                language=item.get("language", "zh"), duration_sec=item.get("duration_sec", 0),
            ))
    return entries


# ============================================================================
# 引擎实现
# ============================================================================

class ParaformerEngine:
    """Streaming Paraformer"""

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
            while self.recognizer.is_ready(stream):
                self.recognizer.decode_stream(stream)
        # tail padding: 静音 padding 让 Paraformer decoder flush 尾部 token
        stream.accept_waveform(16000, [0.0] * 16000)
        while self.recognizer.is_ready(stream):
            self.recognizer.decode_stream(stream)
        stream.input_finished()
        while self.recognizer.is_ready(stream):
            self.recognizer.decode_stream(stream)
        text = self.recognizer.get_result(stream)
        text = re.sub(r"([\u4e00-\u9fa5])\s+([a-zA-Z0-9])", r"\1\2", text)
        text = re.sub(r"([a-zA-Z0-9])\s+([\u4e00-\u9fa5])", r"\1\2", text)
        return text.strip()


class Qwen3RewriteEngine:
    """Qwen3-0.6B Rewrite 本地引擎（C FFI）"""

    def __init__(self, model_dir: str, dylib_path: str):
        self.lib = ctypes.CDLL(dylib_path)
        self.lib.qwen3_rewrite_load.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
        self.lib.qwen3_rewrite_load.restype = ctypes.c_void_p
        self.lib.qwen3_rewrite_text.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.qwen3_rewrite_text.restype = ctypes.c_void_p
        self.lib.qwen3_rewrite_free_string.argtypes = [ctypes.c_void_p]
        self.lib.qwen3_rewrite_free_string.restype = None
        self.lib.qwen3_rewrite_free.argtypes = [ctypes.c_void_p]
        self.lib.qwen3_rewrite_free.restype = None
        self.engine = self.lib.qwen3_rewrite_load(model_dir.encode(), 0, 1)
        if not self.engine:
            raise RuntimeError(f"Failed to load Qwen3 Rewrite from {model_dir}")

    def rewrite(self, text: str) -> str:
        if not text:
            return text
        ptr = self.lib.qwen3_rewrite_text(self.engine, text.encode("utf-8"))
        if not ptr:
            return text
        result = ctypes.string_at(ptr).decode("utf-8")
        self.lib.qwen3_rewrite_free_string(ptr)
        return result

    def close(self):
        if self.engine:
            self.lib.qwen3_rewrite_free(self.engine)
            self.engine = None


class CloudRewriteEngine:
    """SiliconFlow Cloud Rewrite 引擎（OpenAI 兼容 API）"""

    def __init__(self, api_key: str, base_url: str = "https://api.siliconflow.cn/v1",
                 model: str = "Qwen/Qwen3-8B", auth_mode: str = "bearer",
                 no_think: bool = False):
        if auth_mode == "azure":
            headers = {"api-key": api_key}
        else:
            headers = {"Authorization": f"Bearer {api_key}"}
        self.client = httpx.Client(
            base_url=base_url,
            headers=headers,
            timeout=120.0,
        )
        self.model = model
        self.total_input_tokens = 0
        self.total_output_tokens = 0
        self.max_retries = 5
        self.request_delay = 0.0  # seconds between requests
        self.no_think = no_think

    def rewrite(self, text: str) -> str:
        if not text:
            return text
        system_prompt = SYSTEM_PROMPT
        if self.no_think:
            system_prompt = system_prompt + "\n/no_think"
        for attempt in range(self.max_retries):
            try:
                t0 = time.monotonic()
                resp = self.client.post("/chat/completions", json={
                    "model": self.model,
                    "temperature": 0.0,
                    "max_tokens": 2048,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": text},
                    ],
                })
                resp.raise_for_status()
                data = resp.json()
                break
            except (httpx.ReadTimeout, httpx.ConnectTimeout) as e:
                if attempt < self.max_retries - 1:
                    wait = 2 ** attempt
                    print(f"    [RETRY] {e.__class__.__name__}, retrying in {wait}s... ({attempt+1}/{self.max_retries})")
                    time.sleep(wait)
                else:
                    print(f"    [ERROR] {e.__class__.__name__} after {self.max_retries} retries, returning original text")
                    return text
            except httpx.HTTPStatusError as e:
                status = e.response.status_code
                body = e.response.text[:200]
                if status == 429 and attempt < self.max_retries - 1:
                    wait = 3 * (attempt + 1)
                    print(f"    [RETRY] 429 rate limited, retrying in {wait}s... ({attempt+1}/{self.max_retries})")
                    time.sleep(wait)
                elif attempt < self.max_retries - 1 and status >= 500:
                    wait = 2 ** attempt
                    print(f"    [RETRY] HTTP {status}, retrying in {wait}s... ({attempt+1}/{self.max_retries})")
                    time.sleep(wait)
                else:
                    print(f"    [ERROR] HTTP {status}: {body}")
                    return text

        content = data["choices"][0]["message"].get("content") or ""
        usage = data.get("usage", {})
        self.total_input_tokens += usage.get("prompt_tokens", 0)
        self.total_output_tokens += usage.get("completion_tokens", 0)

        # 去除可能的 <think>...</think> 块（Qwen3 thinking mode）
        content = re.sub(r"<think>.*?</think>\s*", "", content, flags=re.DOTALL)

        # Rate limit: delay between requests
        if self.request_delay > 0:
            time.sleep(self.request_delay)

        return content.strip()

    def close(self):
        self.client.close()


# ============================================================================
# Pipeline 封装
# ============================================================================

class ParaformerBaselinePipeline:
    NAME = "Paraformer Pipeline"
    SHORT = "paraformer"

    def __init__(self, asr: ParaformerEngine, csc, punct):
        self.asr = asr
        self.csc = csc
        self.punct = punct

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        if self.csc:
            text = self.csc.correct(text)
        if self.punct:
            text = self.punct.add_punctuation(text)
        return text


class LocalRewritePipeline:
    NAME = "Paraformer + Local Rewrite (0.6B)"
    SHORT = "local_rewrite"

    def __init__(self, asr: ParaformerEngine, rewriter: Qwen3RewriteEngine):
        self.asr = asr
        self.rewriter = rewriter

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        text = self.rewriter.rewrite(text)
        return text


class CloudRewritePipeline:
    NAME = "Paraformer + Cloud Rewrite"
    SHORT = "cloud_rewrite"

    def __init__(self, asr: ParaformerEngine, cloud: CloudRewriteEngine):
        self.asr = asr
        self.cloud = cloud
        self.last_asr_raw = ""  # 诊断用：ASR 原始输出（rewrite 前）

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        self.last_asr_raw = text
        text = self.cloud.rewrite(text)
        return text


# ============================================================================
# 后处理模块 (CSC + 标点，与 benchmark_engines.py 一致)
# ============================================================================

class ChineseSpellingCorrector:
    def __init__(self, model_path: str, vocab_path: str, confidence_threshold: float = 0.9):
        import onnxruntime as ort
        self.session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
        with open(vocab_path) as f:
            self.vocab = [line.strip() for line in f]
        self.token2id = {t: i for i, t in enumerate(self.vocab)}
        self.confidence_threshold = confidence_threshold

    def correct(self, text: str) -> str:
        import numpy as np
        if not text:
            return text
        tokens = ["[CLS]"] + list(text)[:510] + ["[SEP]"]
        input_ids = [self.token2id.get(t, self.token2id.get("[UNK]", 100)) for t in tokens]
        attention_mask = [1] * len(input_ids)
        token_type_ids = [0] * len(input_ids)
        inputs = {
            "input_ids": np.array([input_ids], dtype=np.int64),
            "attention_mask": np.array([attention_mask], dtype=np.int64),
            "token_type_ids": np.array([token_type_ids], dtype=np.int64),
        }
        outputs = self.session.run(None, inputs)
        logits = outputs[0][0]
        result = list(text)
        for i in range(min(len(result), logits.shape[0] - 2)):
            probs = logits[i + 1]
            exp_probs = np.exp(probs - np.max(probs))
            softmax = exp_probs / exp_probs.sum()
            pred_id = int(np.argmax(softmax))
            confidence = float(softmax[pred_id])
            if confidence >= self.confidence_threshold and pred_id < len(self.vocab):
                pred_char = self.vocab[pred_id]
                if pred_char != result[i] and len(pred_char) == 1 and pred_char not in ("[UNK]", "[PAD]", "[CLS]", "[SEP]"):
                    result[i] = pred_char
        return "".join(result)


class PunctuationProcessor:
    def __init__(self, model_dir: str):
        import sherpa_onnx
        self.punct = sherpa_onnx.OfflinePunctuation(
            model=sherpa_onnx.OfflinePunctuationModelConfig(
                ct_transformer=os.path.join(model_dir, "model.int8.onnx"),
            ),
            vocab_size=272727,
        )

    def add_punctuation(self, text: str) -> str:
        if not text:
            return text
        return self.punct.add_punctuation(text)


# ============================================================================
# 报告生成
# ============================================================================

@dataclass
class Result:
    entry: Entry
    engine_name: str
    output_text: str
    cer: float
    elapsed_sec: float


def run_engine(engine, engine_name: str, entries: list[Entry],
               verbose: bool = False) -> list[Result]:
    results = []
    for i, e in enumerate(entries):
        samples, sr = load_wav_as_float32(e.audio_path)
        audio_dur = len(samples) / sr if sr > 0 else 0
        t0 = time.monotonic()
        output = engine.transcribe(samples)
        elapsed = time.monotonic() - t0
        cer = compute_min_cer(output, e.expected_texts)
        results.append(Result(entry=e, engine_name=engine_name,
                              output_text=output, cer=cer, elapsed_sec=elapsed))
        tag = "OK" if cer <= 0.15 else ("WARN" if cer <= 0.30 else "HIGH")
        print(f"  [{i+1:3d}/{len(entries)}] [{tag:4s}] CER={cer:.3f} | {e.id}")
        if verbose:
            print(f"         期望: {e.expected_texts[0]}")
            print(f"         实际: {output}")
            print(f"         耗时: {elapsed:.2f}s")
        # 诊断日志：CER > 0.1 时输出详细信息
        if cer > 0.1:
            print(f"         [DIAG] audio={audio_dur:.2f}s samples={len(samples)} sr={sr}")
            print(f"         [DIAG] 期望: {e.expected_texts[0]}")
            asr_raw = getattr(engine, "last_asr_raw", None)
            if asr_raw is not None:
                print(f"         [DIAG] ASR原始: {asr_raw}")
                print(f"         [DIAG] Rewrite: {output}")
            else:
                print(f"         [DIAG] 输出: {output}")
    return results


def generate_report(
    all_results: dict[str, list[Result]],
    entries: list[Entry],
    cloud_engine: Optional[CloudRewriteEngine],
    cloud_model: str,
    output_path: str,
):
    lines: list[str] = []

    def w(s=""):
        lines.append(s)

    engine_names = list(all_results.keys())
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    w("# Cloud Rewrite vs Local Rewrite 对比评估报告")
    w()
    w(f"*生成时间：{timestamp}*")
    w(f"*测试集：{len(entries)} 条音频（corpus.json + real_manifest.json）*")
    w(f"*Cloud 模型：{cloud_model}*")
    w()
    w("**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。")
    w()
    w("---")
    w()

    # ---- 1. 总体汇总 ----
    w("## 1. 总体 CER 汇总")
    w()
    total_audio = sum(e.duration_sec for e in entries)

    w("| Pipeline | 平均 CER | CER=0 条数 | CER≤0.05 | CER≤0.10 | CER>0.10 | 总推理时长 | RTF |")
    w("|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|")
    for name in engine_names:
        rs = all_results[name]
        avg_cer = sum(r.cer for r in rs) / len(rs)
        perfect = sum(1 for r in rs if r.cer < 0.001)
        le5 = sum(1 for r in rs if r.cer <= 0.05)
        le10 = sum(1 for r in rs if r.cer <= 0.10)
        gt10 = sum(1 for r in rs if r.cer > 0.10)
        total_t = sum(r.elapsed_sec for r in rs)
        rtf = total_t / total_audio if total_audio > 0 else 0
        w(f"| {name} | {avg_cer:.4f} | {perfect}/{len(rs)} | {le5} | {le10} | {gt10} | {total_t:.1f}s | {rtf:.3f}x |")
    w()

    if cloud_engine:
        w(f"> Cloud API 用量：input {cloud_engine.total_input_tokens} tokens, "
          f"output {cloud_engine.total_output_tokens} tokens, "
          f"total {cloud_engine.total_input_tokens + cloud_engine.total_output_tokens} tokens")
        w()

    # ---- 2. 逐条对比 ----
    w("## 2. 逐条对比（含文本）")
    w()

    for e in entries:
        cers = {}
        outputs = {}
        for name in engine_names:
            r = next((r for r in all_results[name] if r.entry.id == e.id), None)
            if r:
                cers[name] = r.cer
                outputs[name] = r.output_text
            else:
                cers[name] = 999
                outputs[name] = ""

        best_name = min(cers, key=cers.get)

        w(f"### {e.id} ({e.category})")
        w()
        w(f"**期望**: {e.expected_texts[0]}")
        w()
        w("| Pipeline | CER | 输出文本 |")
        w("|----------|:---:|---------|")
        for name in engine_names:
            cer_val = cers[name]
            cer_str = "**0**" if cer_val < 0.001 else f"{cer_val:.3f}"
            if name == best_name and cer_val < 999:
                cer_str = f"**{cer_str.replace('**','')}**"
            out = outputs[name]
            w(f"| {name} | {cer_str} | {out} |")
        w()

    # ---- 3. CER 变化分析 ----
    w("## 3. Cloud vs Local 差异分析")
    w()

    local_name = None
    cloud_name = None
    for name in engine_names:
        if "Local" in name:
            local_name = name
        if "Cloud" in name:
            cloud_name = name

    if local_name and cloud_name:
        improved = []
        degraded = []
        same = []

        for e in entries:
            local_r = next((r for r in all_results[local_name] if r.entry.id == e.id), None)
            cloud_r = next((r for r in all_results[cloud_name] if r.entry.id == e.id), None)
            if not local_r or not cloud_r:
                continue
            diff = cloud_r.cer - local_r.cer
            if diff < -0.005:
                improved.append((e, local_r, cloud_r, diff))
            elif diff > 0.005:
                degraded.append((e, local_r, cloud_r, diff))
            else:
                same.append((e, local_r, cloud_r, diff))

        w(f"- Cloud 更好: **{len(improved)}** 条")
        w(f"- 基本相同 (|diff|≤0.5%): **{len(same)}** 条")
        w(f"- Cloud 更差: **{len(degraded)}** 条")
        w()

        if improved:
            w("### Cloud 更好的条目")
            w()
            w("| ID | Local CER | Cloud CER | CER 改善 | 差异说明 |")
            w("|-----|:--------:|:--------:|:--------:|---------|")
            for e, lr, cr, diff in sorted(improved, key=lambda x: x[3]):
                local_short = lr.output_text[:30] + ("…" if len(lr.output_text) > 30 else "")
                cloud_short = cr.output_text[:30] + ("…" if len(cr.output_text) > 30 else "")
                w(f"| {e.id} | {lr.cer:.3f} | {cr.cer:.3f} | {diff:+.3f} | L: {local_short} → C: {cloud_short} |")
            w()

        if degraded:
            w("### Cloud 更差的条目")
            w()
            w("| ID | Local CER | Cloud CER | CER 恶化 | 差异说明 |")
            w("|-----|:--------:|:--------:|:--------:|---------|")
            for e, lr, cr, diff in sorted(degraded, key=lambda x: -x[3]):
                local_short = lr.output_text[:30] + ("…" if len(lr.output_text) > 30 else "")
                cloud_short = cr.output_text[:30] + ("…" if len(cr.output_text) > 30 else "")
                w(f"| {e.id} | {lr.cer:.3f} | {cr.cer:.3f} | {diff:+.3f} | L: {local_short} → C: {cloud_short} |")
            w()

    w("---")
    w()
    w(f"*报告由 `scripts/benchmark_cloud_rewrite.py` 自动生成*")

    report = "\n".join(lines)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        f.write(report)
    print(f"\n报告已保存到: {output_path}")


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Cloud Rewrite vs Local Rewrite CER 对比")
    parser.add_argument("--output", "-o", type=str, default=None,
                        help="输出报告路径 (默认 docs/benchmark-cloud-rewrite.md)")
    parser.add_argument("--entry", type=str, default=None,
                        help="仅运行指定 entry ID（逗号分隔）")
    parser.add_argument("--model", type=str, default="Qwen/Qwen3-8B",
                        help="SiliconFlow 模型名 (默认 Qwen/Qwen3-8B)")
    parser.add_argument("--base-url", type=str, default="https://api.siliconflow.cn/v1",
                        help="API base URL")
    parser.add_argument("--api-key-env", type=str, default="SILICONFLOW_API_KEY",
                        help="环境变量名 (默认 SILICONFLOW_API_KEY)")
    parser.add_argument("--skip-local", action="store_true",
                        help="跳过本地 Rewrite（仅对比 Paraformer vs Cloud）")
    parser.add_argument("--skip-baseline", action="store_true",
                        help="跳过 Paraformer baseline")
    parser.add_argument("--auth-mode", type=str, default="bearer",
                        choices=["bearer", "azure"],
                        help="API 认证方式: bearer (Authorization header) 或 azure (api-key header)")
    parser.add_argument("--no-think", action="store_true",
                        help="禁用 Qwen3 thinking mode（在 system prompt 末尾加 /no_think）")
    parser.add_argument("--request-delay", type=float, default=0.0,
                        help="每次 API 请求后的等待秒数（避免 429 限流）")
    args = parser.parse_args()

    api_key = os.environ.get(args.api_key_env, "")
    if not api_key:
        print(f"[ERROR] 环境变量 {args.api_key_env} 未设置")
        print(f"  请执行: export {args.api_key_env}='sk-xxx'")
        return

    print("=" * 80)
    print("Cloud Rewrite vs Local Rewrite CER 对比评估")
    print(f"Cloud 模型: {args.model} @ {args.base_url}")
    print("=" * 80)

    # 加载测试集
    print("\n[1] 加载测试数据...")
    entries = load_entries()
    if args.entry:
        entry_ids = [eid.strip() for eid in args.entry.split(",")]
        entries = [e for e in entries if e.id in entry_ids]
        if not entries:
            print(f"  [ERROR] 未找到匹配的 entry ID: {args.entry}")
            return
        print(f"  已过滤，仅评估: {', '.join(e.id for e in entries)}")
    print(f"  共 {len(entries)} 条可评估条目")
    verbose = len(entries) <= 5

    # 初始化 Paraformer ASR（共享）
    print("\n[2] 初始化 Paraformer ASR...")
    if not PARAFORMER_MODEL_DIR.exists():
        print(f"  [ERROR] Paraformer 模型不存在: {PARAFORMER_MODEL_DIR}")
        return
    asr = ParaformerEngine(str(PARAFORMER_MODEL_DIR), None)  # 无 ITN
    print(f"  Paraformer 加载成功 (ITN: off)")

    all_results: dict[str, list[Result]] = {}
    step = 3

    # Pipeline 1: Paraformer baseline (CSC + 标点)
    if not args.skip_baseline:
        print(f"\n[{step}] 运行 Paraformer Pipeline（baseline）...")
        step += 1
        csc = None
        punct = None
        csc_model = CSC_MODEL_DIR / "model_int8.onnx"
        csc_vocab = CSC_MODEL_DIR / "vocab.txt"
        if csc_model.exists() and csc_vocab.exists():
            try:
                csc = ChineseSpellingCorrector(str(csc_model), str(csc_vocab))
            except Exception as e:
                print(f"    [WARN] CSC 加载失败: {e}")
        if PUNCT_MODEL_DIR.exists():
            try:
                punct = PunctuationProcessor(str(PUNCT_MODEL_DIR))
            except Exception as e:
                print(f"    [WARN] 标点模型加载失败: {e}")
        itn_asr = ParaformerEngine(str(PARAFORMER_MODEL_DIR),
                                   str(ITN_FST_PATH) if ITN_FST_PATH.exists() else None)
        pipe = ParaformerBaselinePipeline(itn_asr, csc, punct)
        print(f"  开始评估 (ITN: {'on' if ITN_FST_PATH.exists() else 'off'}, "
              f"CSC: {'on' if csc else 'off'}, 标点: {'on' if punct else 'off'})...")
        all_results[ParaformerBaselinePipeline.NAME] = run_engine(
            pipe, ParaformerBaselinePipeline.NAME, entries, verbose)

    # Pipeline 2: Local Qwen3-0.6B LoRA Rewrite
    if not args.skip_local:
        print(f"\n[{step}] 运行 Local Rewrite Pipeline (Qwen3-0.6B LoRA)...")
        step += 1
        if QWEN3_REWRITE_DYLIB.exists() and QWEN3_REWRITE_MODEL_DIR.exists():
            rewriter = Qwen3RewriteEngine(str(QWEN3_REWRITE_MODEL_DIR), str(QWEN3_REWRITE_DYLIB))
            pipe = LocalRewritePipeline(asr, rewriter)
            print(f"  本地 Rewrite 引擎加载成功，开始评估...")
            all_results[LocalRewritePipeline.NAME] = run_engine(
                pipe, LocalRewritePipeline.NAME, entries, verbose)
            rewriter.close()
        else:
            print(f"  [SKIP] 本地 Rewrite 模型或 dylib 不存在")

    # Pipeline 3: Cloud Rewrite (SiliconFlow)
    print(f"\n[{step}] 运行 Cloud Rewrite Pipeline ({args.model})...")
    step += 1
    cloud = CloudRewriteEngine(api_key, args.base_url, args.model, args.auth_mode, args.no_think)
    cloud.request_delay = args.request_delay
    cloud_pipe = CloudRewritePipeline(asr, cloud)
    # 更新 NAME 显示模型
    CloudRewritePipeline.NAME = f"Paraformer + Cloud Rewrite ({args.model.split('/')[-1]})"
    print(f"  Cloud 引擎初始化成功，开始评估...")
    all_results[CloudRewritePipeline.NAME] = run_engine(
        cloud_pipe, CloudRewritePipeline.NAME, entries, verbose)

    print(f"\n  Cloud API 总用量: input={cloud.total_input_tokens} tok, "
          f"output={cloud.total_output_tokens} tok")

    # 生成报告
    print(f"\n[{step}] 生成对比报告...")
    output = args.output or str(PROJECT_ROOT / "docs" / "benchmark-cloud-rewrite.md")
    generate_report(all_results, entries, cloud, args.model, output)

    cloud.close()
    print("\n评估完成。")


if __name__ == "__main__":
    main()
