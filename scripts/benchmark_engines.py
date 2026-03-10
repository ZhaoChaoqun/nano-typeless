#!/usr/bin/env python3
"""
ASR Pipeline 量化对比评估脚本

对比 4 个完整 Pipeline（与产品一致）：
  1. Qwen3-ASR Pipeline 离线（内置 ITN + 标点 + 纠错）
  2. Qwen3-ASR Pipeline 流式（chunk + rollback，内置 ITN + 标点 + 纠错）
  3. Paraformer Pipeline（ASR + ITN → CSC → CT-Transformer 标点）
  4. SenseVoice Pipeline（ASR + 内置ITN → CSC → CT-Transformer 标点）

使用项目已有测试语料（corpus.json + real_manifest.json），
计算逐条 CER 并输出 Markdown 报告。

用法：
    uv run --with sherpa-onnx --with onnxruntime python3 scripts/benchmark_engines.py
    uv run --with sherpa-onnx --with onnxruntime python3 scripts/benchmark_engines.py --output docs/benchmark-report.md
    uv run --with sherpa-onnx --with onnxruntime python3 scripts/benchmark_engines.py --pipelines paraformer --entry ascend_cs_003
"""

import argparse
import ctypes
import json
import math
import os
import re
import struct
import time
import wave
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

import numpy as np

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
CSC_MODEL_DIR = MODELS_DIR / "macbert4csc-base-chinese"
PUNCT_MODEL_DIR = MODELS_DIR / "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8"

QWEN_DYLIB = PROJECT_ROOT / "Frameworks" / "qwen-asr" / "lib" / "libqwen_asr.dylib"
QWEN3_REWRITE_DYLIB = PROJECT_ROOT / "Frameworks" / "qwen3-rewrite" / "lib" / "libqwen3_rewrite.dylib"
QWEN3_REWRITE_MODEL_DIR = Path.home() / "Github" / "Qwen3-0.6B" / "models" / "Qwen3-0.6B-rewrite-lora"
QWEN3_REWRITE_BASE_MODEL_DIR = Path.home() / "Github" / "QwenASR" / "qwen3-asr-0.6b"

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
# CER 计算（保留标点）
# ============================================================================

def normalize_text(text: str) -> str:
    """归一化文本：仅 lower + 去空格，保留标点符号"""
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
    """多候选 CER：取所有候选中的最小值"""
    if not expected_texts:
        return 1.0
    return min(compute_cer(actual, e) for e in expected_texts)


# ============================================================================
# 后处理模块
# ============================================================================

class ChineseSpellingCorrector:
    """macbert4csc INT8 中文拼写纠错（Python 等价实现，与 Swift 版逻辑对齐）"""

    def __init__(self, model_path: str, vocab_path: str, confidence_threshold: float = 0.9):
        import onnxruntime as ort

        # 加载词表
        self.token2id: dict[str, int] = {}
        self.id2token: dict[int, str] = {}
        with open(vocab_path, encoding="utf-8") as f:
            for idx, line in enumerate(f):
                token = line.strip()
                if token:
                    self.token2id[token] = idx
                    self.id2token[idx] = token

        self.vocab_size = max(self.id2token.keys()) + 1
        self.cls_id = self.token2id.get("[CLS]", 101)
        self.sep_id = self.token2id.get("[SEP]", 102)
        self.unk_id = self.token2id.get("[UNK]", 100)
        self.confidence_threshold = confidence_threshold

        # 加载 ONNX 模型
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2
        self.session = ort.InferenceSession(model_path, opts, providers=["CPUExecutionProvider"])
        print(f"    CSC 模型加载成功 (vocab={self.vocab_size})")

    @staticmethod
    def _is_chinese(char: str) -> bool:
        cp = ord(char)
        return (0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF or
                0x20000 <= cp <= 0x2A6DF or 0x2A700 <= cp <= 0x2B73F or
                0x2B740 <= cp <= 0x2B81F or 0x2B820 <= cp <= 0x2CEAF or
                0xF900 <= cp <= 0xFAFF or 0x2F800 <= cp <= 0x2FA1F)

    def _tokenize(self, text: str) -> list[int]:
        ids = [self.cls_id]
        for ch in text:
            if ch in self.token2id:
                ids.append(self.token2id[ch])
            elif ch.lower() in self.token2id:
                ids.append(self.token2id[ch.lower()])
            else:
                ids.append(self.unk_id)
        ids.append(self.sep_id)
        return ids

    def correct(self, text: str) -> str:
        if not text:
            return text

        chars = list(text)
        input_ids = self._tokenize(text)
        seq_len = len(input_ids)

        if seq_len <= 2 or seq_len > 512:
            return text

        # 准备输入
        ids_arr = np.array([input_ids], dtype=np.int64)
        att_mask = np.ones((1, seq_len), dtype=np.int64)
        token_types = np.zeros((1, seq_len), dtype=np.int64)

        # 推理
        outputs = self.session.run(
            ["logits"],
            {"input_ids": ids_arr, "attention_mask": att_mask, "token_type_ids": token_types},
        )
        logits = outputs[0][0]  # shape: (seq_len, vocab_size)

        # 逐位置纠错
        corrected = list(chars)
        correction_count = 0
        chinese_char_count = 0

        for i in range(1, seq_len - 1):
            char_idx = i - 1
            if char_idx >= len(chars):
                break

            if not self._is_chinese(chars[char_idx]):
                continue
            chinese_char_count += 1

            row = logits[i]
            max_idx = int(np.argmax(row))
            max_val = row[max_idx]

            original_id = input_ids[i]
            if max_idx != original_id and max_idx != self.unk_id:
                original_logit = row[original_id]
                logit_diff = max_val - original_logit

                # 条件 1：logit 差值 > 5.0
                if logit_diff <= 5.0:
                    continue

                # 条件 2：softmax top-1 > 0.9
                exp_sum = np.sum(np.exp(row - max_val))
                top_prob = 1.0 / exp_sum
                if top_prob <= 0.9:
                    continue

                corrected_token = self.id2token.get(max_idx, "")
                if len(corrected_token) == 1 and self._is_chinese(corrected_token):
                    corrected[char_idx] = corrected_token
                    correction_count += 1

        # Sanity check: 纠正 > 20% 则丢弃
        if correction_count > 0 and chinese_char_count > 0:
            ratio = correction_count / chinese_char_count
            if ratio > 0.2:
                return text
            return "".join(corrected)

        return text


class PunctuationProcessor:
    """CT-Transformer 标点处理器（通过 sherpa-onnx Python API）"""

    def __init__(self, model_dir: str):
        import sherpa_onnx

        model_path = os.path.join(model_dir, "model.int8.onnx")
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"标点模型不存在: {model_path}")

        config = sherpa_onnx.OfflinePunctuationConfig(
            model=sherpa_onnx.OfflinePunctuationModelConfig(
                ct_transformer=model_path,
                num_threads=2,
                provider="cpu",
            )
        )
        self.punct = sherpa_onnx.OfflinePunctuation(config)
        print(f"    标点模型加载成功")

    def add_punctuation(self, text: str) -> str:
        if not text:
            return text
        return self.punct.add_punctuation(text)


# ============================================================================
# ASR 引擎（底层）
# ============================================================================

class QwenASROfflineEngine:
    """Qwen3-ASR 离线模式：一次性传入全部音频"""

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

    def __init__(self, model_dir: str, dylib_path: str):
        self.lib = ctypes.CDLL(dylib_path)
        self._setup(self.lib)
        self.engine = self.lib.qwen_asr_load_model(model_dir.encode(), 4, 0)
        if not self.engine:
            raise RuntimeError(f"Failed to load Qwen3-ASR from {model_dir}")
        self.lib.qwen_asr_set_language(self.engine, b"chinese")
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
        # 流式 Paraformer 编码器有 lookahead 需求，
        # 需要足够静音 padding + input_finished 才能完整解码尾部 token
        stream.accept_waveform(16000, [0.0] * 16000)  # 1s silence padding
        while self.recognizer.is_ready(stream):
            self.recognizer.decode_stream(stream)
        stream.input_finished()
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


class Qwen3RewriteEngine:
    """Qwen3-0.6B Rewrite 后处理引擎（C FFI）"""

    def __init__(self, model_dir: str, dylib_path: str):
        self.lib = ctypes.CDLL(dylib_path)
        self._setup(self.lib)
        self.engine = self.lib.qwen3_rewrite_load(model_dir.encode(), 0, 1)
        if not self.engine:
            raise RuntimeError(f"Failed to load Qwen3 Rewrite from {model_dir}")

    @staticmethod
    def _setup(lib):
        lib.qwen3_rewrite_load.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
        lib.qwen3_rewrite_load.restype = ctypes.c_void_p
        lib.qwen3_rewrite_text.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.qwen3_rewrite_text.restype = ctypes.c_void_p
        lib.qwen3_rewrite_free_string.argtypes = [ctypes.c_void_p]
        lib.qwen3_rewrite_free_string.restype = None
        lib.qwen3_rewrite_free.argtypes = [ctypes.c_void_p]
        lib.qwen3_rewrite_free.restype = None

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


# ============================================================================
# Pipeline 封装（与产品架构一致）
# ============================================================================

class QwenASRPipeline:
    """Pipeline: Qwen3-ASR 离线（内置 ITN + 标点 + 纠错）"""
    NAME = "Qwen3-ASR (离线)"
    SHORT = "qwen"
    DESC = "内置 ITN + 标点 + 纠错"

    def __init__(self, model_dir: str, dylib_path: str):
        self.asr = QwenASROfflineEngine(model_dir, dylib_path)

    def transcribe(self, samples: list[float]) -> str:
        return self.asr.transcribe(samples)

    def close(self):
        self.asr.close()


class QwenASRStreamPipeline:
    """Pipeline: Qwen3-ASR 流式 chunk + rollback（内置 ITN + 标点 + 纠错）"""
    NAME = "Qwen3-ASR (流式)"
    SHORT = "qwen_stream"
    DESC = "流式 chunk+rollback, 内置 ITN + 标点 + 纠错"

    def __init__(self, model_dir: str, dylib_path: str):
        self.asr = QwenASRStreamEngine(model_dir, dylib_path)

    def transcribe(self, samples: list[float]) -> str:
        return self.asr.transcribe(samples)

    def close(self):
        self.asr.close()


class ParaformerPipeline:
    """Pipeline: Streaming Paraformer + ITN → CSC → CT-Transformer 标点"""
    NAME = "Paraformer Pipeline"
    SHORT = "paraformer"
    DESC = "ASR + ITN → CSC → 标点"

    def __init__(self, model_dir: str, itn_fst: Optional[str],
                 csc: Optional[ChineseSpellingCorrector],
                 punct: Optional[PunctuationProcessor]):
        self.asr = ParaformerEngine(model_dir, itn_fst)
        self.csc = csc
        self.punct = punct

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        if self.csc:
            text = self.csc.correct(text)
        if self.punct:
            text = self.punct.add_punctuation(text)
        return text

    def close(self):
        self.asr.close()


class SenseVoicePipeline:
    """Pipeline: SenseVoice Nano (内置ITN) → CSC → CT-Transformer 标点"""
    NAME = "SenseVoice Pipeline"
    SHORT = "sensevoice"
    DESC = "ASR + 内置ITN → CSC → 标点"

    def __init__(self, model_dir: str,
                 csc: Optional[ChineseSpellingCorrector],
                 punct: Optional[PunctuationProcessor]):
        self.asr = SenseVoiceEngine(model_dir)
        self.csc = csc
        self.punct = punct

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        if self.csc:
            text = self.csc.correct(text)
        if self.punct:
            text = self.punct.add_punctuation(text)
        return text

    def close(self):
        self.asr.close()


class ParaformerQwen3RewritePipeline:
    """Pipeline: Streaming Paraformer + Qwen3-0.6B Rewrite 一站式后处理"""
    NAME = "Paraformer + Qwen3 Rewrite"
    SHORT = "paraformer_rewrite"
    DESC = "ASR + Qwen3-0.6B LoRA 一站式后处理（ITN + 标点 + CSC）"

    def __init__(self, model_dir: str, itn_fst: Optional[str],
                 rewriter: Qwen3RewriteEngine):
        self.asr = ParaformerEngine(model_dir, itn_fst)
        self.rewriter = rewriter

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        text = self.rewriter.rewrite(text)
        return text

    def close(self):
        self.asr.close()


class ParaformerQwen3RewriteBasePipeline:
    """Pipeline: Streaming Paraformer + Qwen3-0.6B Base (ASR原始LLM) Rewrite"""
    NAME = "Paraformer + Qwen3 Rewrite (Base)"
    SHORT = "paraformer_rewrite_base"
    DESC = "ASR + Qwen3-0.6B Base（无LoRA）一站式后处理"

    def __init__(self, model_dir: str, itn_fst: Optional[str],
                 rewriter: Qwen3RewriteEngine):
        self.asr = ParaformerEngine(model_dir, itn_fst)
        self.rewriter = rewriter

    def transcribe(self, samples: list[float]) -> str:
        text = self.asr.transcribe(samples)
        text = self.rewriter.rewrite(text)
        return text

    def close(self):
        self.asr.close()


# ============================================================================
# 数据结构
# ============================================================================

@dataclass
class Entry:
    id: str
    category: str
    expected_texts: list[str]
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
# 评估与报告生成
# ============================================================================

def run_engine(engine, engine_name: str, entries: list[Entry], verbose: bool = False) -> list[Result]:
    results = []
    for i, e in enumerate(entries):
        samples, _ = load_wav_as_float32(e.audio_path)
        t0 = time.monotonic()
        output = engine.transcribe(samples)
        elapsed = time.monotonic() - t0
        cer = compute_min_cer(output, e.expected_texts)
        results.append(Result(entry=e, engine_name=engine_name, output_text=output, cer=cer, elapsed_sec=elapsed))
        tag = "OK" if cer <= 0.15 else ("WARN" if cer <= 0.30 else "HIGH")
        print(f"  [{i+1:3d}/{len(entries)}] [{tag:4s}] CER={cer:.3f} | {e.id}")
        if verbose:
            print(f"         期望: {e.expected_texts[0]}")
            print(f"         实际: {output}")
            print(f"         耗时: {elapsed:.2f}s")
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

    w(f"# ASR Pipeline 量化对比评估报告")
    w()
    w(f"*生成时间：{timestamp}*")
    w(f"*测试集：{len(entries)} 条音频（corpus.json + real_manifest.json）*")
    w(f"*Pipeline：{', '.join(engine_names)}*")
    w()
    w("**CER 计算方式**：保留标点符号，仅做 lower + 去空格后计算字符错误率。")
    w()
    w("---")
    w()

    # ---- 1. 总体汇总 ----
    w("## 1. 总体 CER 汇总")
    w()
    w("| Pipeline | 平均 CER | CER=0 条数 | CER≤0.10 | CER≤0.20 | CER>0.20 | 总推理时长 | RTF |")
    w("|----------|:-------:|:---------:|:-------:|:-------:|:-------:|:---------:|:---:|")
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
        short = name.split("(")[0].strip()[:14]
        header += f" {short} |"
        sep += ":------:|"
    header += " 最佳 |"
    sep += "------|"
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
        row += f" {best.split('(')[0].strip()[:14]} |"
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
    row += f" **{best.split('(')[0].strip()[:14]}** |"
    w(row)
    w()

    # ---- 3. 逐条对比 ----
    w("## 3. 逐条 CER 对比")
    w()
    header = "| ID | 类别 |"
    sep = "|-----|------|"
    for name in engine_names:
        short = name.replace("Pipeline", "").strip()[:12]
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
        row += f" {best_name.replace('Pipeline','').strip()[:10]} |"
        w(row)
    w()

    # ---- 4. 推理速度 ----
    w("## 4. 推理速度对比")
    w()
    w("| Pipeline | 总音频 | 总推理 | RTF | 平均/条 |")
    w("|----------|:-----:|:-----:|:---:|:------:|")
    for name in engine_names:
        rs = all_results[name]
        t_audio = sum(r.entry.duration_sec for r in rs)
        t_infer = sum(r.elapsed_sec for r in rs)
        rtf = t_infer / t_audio if t_audio > 0 else 0
        avg = t_infer / len(rs)
        w(f"| {name} | {t_audio:.0f}s | {t_infer:.1f}s | {rtf:.3f}x | {avg:.2f}s |")
    w()

    # ---- 5. 错误案例分析 ----
    w("## 5. 各 Pipeline 识别错误案例详细分析")
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
            expected_norm = normalize_text(r.entry.expected_texts[0])
            actual_norm = normalize_text(r.output_text)

            # 分析错误类型
            error_types = []
            # 繁体字检测
            trad_indicators = set("書學數點機語認識經過國開會從發時問題這個應該進來說長給對門關電話東風車後飛運動員")
            found_trad = set(r.output_text) & trad_indicators
            if found_trad and not (set(r.entry.expected_texts[0]) & found_trad):
                error_types.append("繁体字输出")

            # 英文词汇错误
            en_expected = set(re.findall(r"[a-zA-Z]+", r.entry.expected_texts[0].lower()))
            en_actual = set(re.findall(r"[a-zA-Z]+", r.output_text.lower()))
            missed_en = en_expected - en_actual
            if missed_en:
                error_types.append(f"英文词丢失: {','.join(list(missed_en)[:3])}")

            # 数字格式差异
            if re.search(r"\d", r.entry.expected_texts[0]) or re.search(r"[一二三四五六七八九十百千万亿]", r.entry.expected_texts[0]):
                if r.cer > 0.1:
                    error_types.append("数字/量词")

            # 截断
            if len(actual_norm) < len(expected_norm) * 0.7:
                error_types.append("截断")
            elif len(actual_norm) > len(expected_norm) * 1.4:
                error_types.append("幻觉/冗余")

            # 标点差异
            zh_punct = set("，。！？、；：""''（）【】《》…—·")
            en_punct = set(",.!?;:'\"()[]<>")
            exp_puncts = set(r.entry.expected_texts[0]) & (zh_punct | en_punct)
            act_puncts = set(r.output_text) & (zh_punct | en_punct)
            if exp_puncts != act_puncts and r.cer <= 0.15:
                error_types.append("标点差异")

            # 同音字
            if not error_types and r.cer <= 0.3:
                error_types.append("同音字/近音字")

            if not error_types:
                error_types.append("综合误差")

            err_str = ", ".join(error_types)
            exp_short = r.entry.expected_texts[0][:40] + ("…" if len(r.entry.expected_texts[0]) > 40 else "")
            out_short = r.output_text[:40] + ("…" if len(r.output_text) > 40 else "")
            cer_str = f"{r.cer:.3f}" if r.cer <= 1.0 else f"{r.cer:.1f}"
            w(f"| {i+1} | {r.entry.id} | {cer_str} | {exp_short} | {out_short} | {err_str} |")

        w()

    # ---- 6. 综合分析 ----
    w("## 6. 综合分析与建议")
    w()

    # 找每个类别的最佳 Pipeline
    w("### 各场景最佳 Pipeline 推荐")
    w()
    w("| 场景 | 推荐 Pipeline | CER |")
    w("|------|--------------|:---:|")

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
        w(f"| {cat} | {best} | {cer:.3f} |")
    w()

    w("### Pipeline 特点总结")
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
    parser = argparse.ArgumentParser(description="ASR Pipeline 量化对比评估")
    parser.add_argument("--output", "-o", type=str, default=None, help="输出 Markdown 报告路径")
    parser.add_argument("--pipelines", type=str, default="all",
                        help="要评估的 Pipeline，逗号分隔：qwen,qwen_stream,paraformer,paraformer_rewrite,sensevoice (默认 all)")
    parser.add_argument("--entry", type=str, default=None,
                        help="仅运行指定 entry ID（逗号分隔可指定多条），例如：--entry ascend_cs_003")
    args = parser.parse_args()

    if args.pipelines == "all":
        pipeline_list = ["qwen", "qwen_stream", "paraformer", "paraformer_rewrite", "paraformer_rewrite_base", "sensevoice"]
    else:
        pipeline_list = [e.strip() for e in args.pipelines.split(",")]

    print("=" * 100)
    print("ASR Pipeline 量化对比评估")
    print("=" * 100)

    print("\n[1] 加载测试数据...")
    entries = load_entries()

    # 按 entry ID 过滤
    if args.entry:
        entry_ids = [eid.strip() for eid in args.entry.split(",")]
        entries = [e for e in entries if e.id in entry_ids]
        if not entries:
            print(f"  [ERROR] 未找到匹配的 entry ID: {args.entry}")
            return
        print(f"  已过滤，仅评估: {', '.join(e.id for e in entries)}")

    print(f"  共 {len(entries)} 条可评估条目")
    verbose = len(entries) <= 5
    cats = {}
    for e in entries:
        cats.setdefault(e.category, 0)
        cats[e.category] += 1
    for cat, n in sorted(cats.items()):
        print(f"    {cat}: {n} 条")

    # 初始化共享后处理模块
    csc = None
    punct = None
    rewriter = None
    rewriter_base = None
    need_postprocessing = "paraformer" in pipeline_list or "sensevoice" in pipeline_list
    need_rewriter = "paraformer_rewrite" in pipeline_list
    need_rewriter_base = "paraformer_rewrite_base" in pipeline_list

    if need_postprocessing:
        print("\n[2] 初始化共享后处理模块...")

        # CSC
        csc_model = CSC_MODEL_DIR / "model_int8.onnx"
        csc_vocab = CSC_MODEL_DIR / "vocab.txt"
        if csc_model.exists() and csc_vocab.exists():
            try:
                csc = ChineseSpellingCorrector(str(csc_model), str(csc_vocab))
            except Exception as e:
                print(f"    [WARN] CSC 加载失败: {e}")
        else:
            print(f"    [WARN] CSC 模型不存在，跳过纠错")

        # 标点
        if PUNCT_MODEL_DIR.exists():
            try:
                punct = PunctuationProcessor(str(PUNCT_MODEL_DIR))
            except Exception as e:
                print(f"    [WARN] 标点模型加载失败: {e}")
        else:
            print(f"    [WARN] 标点模型不存在，跳过标点")

    all_results: dict[str, list[Result]] = {}
    step = 2
    if need_postprocessing:
        step += 1

    # Qwen3-ASR Pipeline (离线)
    if "qwen" in pipeline_list:
        print(f"\n[{step}] 初始化 Qwen3-ASR (离线) Pipeline...")
        step += 1
        if QWEN_DYLIB.exists() and QWEN_MODEL_DIR.exists():
            pipe = QwenASRPipeline(str(QWEN_MODEL_DIR), str(QWEN_DYLIB))
            print(f"  加载成功，开始评估...")
            all_results[QwenASRPipeline.NAME] = run_engine(pipe, QwenASRPipeline.NAME, entries, verbose)
            pipe.close()
        else:
            print(f"  [SKIP] 模型或 dylib 不存在")

    # Qwen3-ASR Pipeline (流式)
    if "qwen_stream" in pipeline_list:
        print(f"\n[{step}] 初始化 Qwen3-ASR (流式) Pipeline...")
        step += 1
        if QWEN_DYLIB.exists() and QWEN_MODEL_DIR.exists():
            pipe = QwenASRStreamPipeline(str(QWEN_MODEL_DIR), str(QWEN_DYLIB))
            print(f"  加载成功，开始评估...")
            all_results[QwenASRStreamPipeline.NAME] = run_engine(pipe, QwenASRStreamPipeline.NAME, entries, verbose)
            pipe.close()
        else:
            print(f"  [SKIP] 模型或 dylib 不存在")

    # Paraformer Pipeline
    if "paraformer" in pipeline_list:
        print(f"\n[{step}] 初始化 Paraformer Pipeline...")
        step += 1
        if PARAFORMER_MODEL_DIR.exists():
            itn = str(ITN_FST_PATH) if ITN_FST_PATH.exists() else None
            pipe = ParaformerPipeline(str(PARAFORMER_MODEL_DIR), itn, csc, punct)
            print(f"  加载成功 (ITN: {'on' if itn else 'off'}, CSC: {'on' if csc else 'off'}, 标点: {'on' if punct else 'off'})，开始评估...")
            all_results[ParaformerPipeline.NAME] = run_engine(pipe, ParaformerPipeline.NAME, entries, verbose)
            pipe.close()
        else:
            print(f"  [SKIP] 模型不存在")

    # SenseVoice Pipeline
    if "sensevoice" in pipeline_list:
        print(f"\n[{step}] 初始化 SenseVoice Pipeline...")
        step += 1
        if SENSEVOICE_MODEL_DIR.exists():
            pipe = SenseVoicePipeline(str(SENSEVOICE_MODEL_DIR), csc, punct)
            print(f"  加载成功 (CSC: {'on' if csc else 'off'}, 标点: {'on' if punct else 'off'})，开始评估...")
            all_results[SenseVoicePipeline.NAME] = run_engine(pipe, SenseVoicePipeline.NAME, entries, verbose)
            pipe.close()
        else:
            print(f"  [SKIP] 模型不存在")

    # Paraformer + Qwen3 Rewrite Pipeline
    if "paraformer_rewrite" in pipeline_list:
        print(f"\n[{step}] 初始化 Paraformer + Qwen3 Rewrite Pipeline...")
        step += 1
        if PARAFORMER_MODEL_DIR.exists() and QWEN3_REWRITE_DYLIB.exists() and QWEN3_REWRITE_MODEL_DIR.exists():
            if not rewriter:
                try:
                    rewriter = Qwen3RewriteEngine(str(QWEN3_REWRITE_MODEL_DIR), str(QWEN3_REWRITE_DYLIB))
                    print(f"    Qwen3 Rewrite 引擎加载成功")
                except Exception as e:
                    print(f"    [WARN] Qwen3 Rewrite 引擎加载失败: {e}")
            if rewriter:
                pipe = ParaformerQwen3RewritePipeline(str(PARAFORMER_MODEL_DIR), None, rewriter)
                print(f"  加载成功 (ITN: off)，开始评估...")
                all_results[ParaformerQwen3RewritePipeline.NAME] = run_engine(pipe, ParaformerQwen3RewritePipeline.NAME, entries, verbose)
                pipe.close()
                # Release LoRA rewriter before loading Base to save memory
                rewriter.close()
                rewriter = None
            else:
                print(f"  [SKIP] Qwen3 Rewrite 引擎不可用")
        else:
            missing = []
            if not PARAFORMER_MODEL_DIR.exists(): missing.append("Paraformer 模型")
            if not QWEN3_REWRITE_DYLIB.exists(): missing.append("qwen3_rewrite dylib")
            if not QWEN3_REWRITE_MODEL_DIR.exists(): missing.append("Qwen3 Rewrite 模型")
            print(f"  [SKIP] 缺少: {', '.join(missing)}")

    # Paraformer + Qwen3 Rewrite Base (ASR 原始 LLM) Pipeline
    if "paraformer_rewrite_base" in pipeline_list:
        print(f"\n[{step}] 初始化 Paraformer + Qwen3 Rewrite (Base) Pipeline...")
        step += 1
        if PARAFORMER_MODEL_DIR.exists() and QWEN3_REWRITE_DYLIB.exists() and QWEN3_REWRITE_BASE_MODEL_DIR.exists():
            if not rewriter_base:
                try:
                    rewriter_base = Qwen3RewriteEngine(str(QWEN3_REWRITE_BASE_MODEL_DIR), str(QWEN3_REWRITE_DYLIB))
                    print(f"    Qwen3 Rewrite (Base) 引擎加载成功")
                except Exception as e:
                    print(f"    [WARN] Qwen3 Rewrite (Base) 引擎加载失败: {e}")
            if rewriter_base:
                pipe = ParaformerQwen3RewriteBasePipeline(str(PARAFORMER_MODEL_DIR), None, rewriter_base)
                print(f"  加载成功 (ITN: off)，开始评估...")
                all_results[ParaformerQwen3RewriteBasePipeline.NAME] = run_engine(pipe, ParaformerQwen3RewriteBasePipeline.NAME, entries, verbose)
                pipe.close()
            else:
                print(f"  [SKIP] Qwen3 Rewrite (Base) 引擎不可用")
        else:
            missing = []
            if not PARAFORMER_MODEL_DIR.exists(): missing.append("Paraformer 模型")
            if not QWEN3_REWRITE_DYLIB.exists(): missing.append("qwen3_rewrite dylib")
            if not QWEN3_REWRITE_BASE_MODEL_DIR.exists(): missing.append("Qwen3 ASR Base 模型")
            print(f"  [SKIP] 缺少: {', '.join(missing)}")

    if not all_results:
        print("\n没有可用的 Pipeline，退出。")
        return

    print(f"\n[{step}] 生成对比报告...")
    output = args.output or str(PROJECT_ROOT / "docs" / "benchmark-report.md")
    generate_report(all_results, entries, output)
    print("\n评估完成。")


if __name__ == "__main__":
    main()
