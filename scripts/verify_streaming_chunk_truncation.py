#!/usr/bin/env python3
"""
用原生 ONNX Runtime 模拟 sherpa-onnx 的流式 chunk 推理，
直接复现 cs_edge_008 和 wenet_net_001 的尾部截断。

sherpa-onnx 流式参数（硬编码）:
  chunk_size_ = 61 raw fbank frames (≈0.61s)
  left_chunk_size_ = 5 LFR frames of left context
  right_chunk_size_ = 3 LFR frames of right context

关键截断机制:
  每个 chunk 的 encoder 输出中，左右上下文区域的 alphas 被强制置零，
  防止重复 token。但如果音频末尾落在右上下文区域，token 就永远丢失了。

用法:
    cd ~/Github/typeless
    uv run --with onnxruntime --with kaldi-native-fbank --with soundfile \
        python3 scripts/verify_streaming_chunk_truncation.py
"""
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

# 复用 verify_onnx_tail_fix.py 中的基础函数
from verify_onnx_tail_fix import (
    load_audio,
    extract_fbank,
    apply_lfr,
    apply_cmvn,
    load_tokens,
    ids_to_text,
    cif_integrate,
)

MODEL_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Nano Typeless"
    / "models"
    / "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
)
FIXTURES = Path(__file__).resolve().parent.parent / "Tests" / "fixtures" / "audio"

# sherpa-onnx 流式参数
CHUNK_SIZE = 61  # raw fbank frames per chunk
LEFT_CHUNK = 5   # LFR frames of left context
RIGHT_CHUNK = 3  # LFR frames of right context


def streaming_inference(
    enc_sess: ort.InferenceSession,
    dec_sess: ort.InferenceSession,
    tokens: dict[int, str],
    neg_mean: np.ndarray,
    inv_stddev: np.ndarray,
    audio_path: Path,
    zero_right_context: bool = True,
) -> tuple[str, dict]:
    """
    模拟 sherpa-onnx 的流式 chunk-by-chunk 推理。

    zero_right_context: 如果 True，模拟 sherpa-onnx 将右上下文 alphas 置零。
                        如果 False，不置零（验证截断确实来自 alpha 零化）。
    """
    samples, sr = load_audio(audio_path)
    fbank = extract_fbank(samples, sr)
    T_fbank = fbank.shape[0]

    # LFR + CMVN 对全部特征
    lfr_all = apply_lfr(fbank, m=7, n=6)
    cmvn_all = apply_cmvn(lfr_all, neg_mean, inv_stddev)
    T_lfr = cmvn_all.shape[0]

    # 模拟 chunk 切分
    # sherpa-onnx: 每次处理 61 raw frames → ~10 LFR frames
    # 加上 left(5) + right(3) 上下文 → ~18 LFR frames 送入 encoder
    #
    # LFR frame 对应关系: LFR frame i 对应 raw frame i*6 开始的 7 帧
    # 每个 chunk 的 LFR "center" 区域 ≈ 10 帧

    lfr_chunk_size = 10  # 每个 chunk 的有效 LFR 帧数

    all_enc_pieces = []
    all_alpha_pieces = []
    chunk_details = []

    n_chunks = (T_lfr + lfr_chunk_size - 1) // lfr_chunk_size

    for c in range(n_chunks):
        # 当前 chunk 的中心区域
        center_start = c * lfr_chunk_size
        center_end = min(center_start + lfr_chunk_size, T_lfr)

        # 加上左右上下文
        ctx_start = max(0, center_start - LEFT_CHUNK)
        ctx_end = min(T_lfr, center_end + RIGHT_CHUNK)

        chunk_feats = cmvn_all[ctx_start:ctx_end]

        # Encoder forward
        speech = chunk_feats[np.newaxis, :, :].astype(np.float32)
        speech_lengths = np.array([chunk_feats.shape[0]], dtype=np.int32)
        enc, enc_len, alphas = enc_sess.run(
            ["enc", "enc_len", "alphas"],
            {"speech": speech, "speech_lengths": speech_lengths},
        )
        enc = enc[0]      # [T_chunk, 512]
        alphas = alphas[0] # [T_chunk]

        # 计算在 chunk 输出中，center 区域对应的索引
        left_ctx_frames = center_start - ctx_start  # 左上下文帧数
        right_ctx_frames = ctx_end - center_end      # 右上下文帧数
        center_len = center_end - center_start

        if zero_right_context:
            # sherpa-onnx: 将左上下文和右上下文的 alphas 置零
            if left_ctx_frames > 0:
                alphas[:left_ctx_frames] = 0.0
            if right_ctx_frames > 0:
                alphas[-right_ctx_frames:] = 0.0

        # 只取 center 区域的 encoder 输出 (不含左右上下文)
        # 但 sherpa-onnx 实际上取整个输出但 alpha 置零来屏蔽上下文
        # 为了更准确模拟，我们保留全部输出但用 alpha=0 来屏蔽
        all_enc_pieces.append(enc[left_ctx_frames:left_ctx_frames + center_len])
        all_alpha_pieces.append(alphas[left_ctx_frames:left_ctx_frames + center_len])

        chunk_details.append({
            "chunk": c,
            "ctx_range": f"[{ctx_start}:{ctx_end}]",
            "center_range": f"[{center_start}:{center_end}]",
            "alpha_sum_full": float(alphas.sum()),
            "alpha_sum_center": float(alphas[left_ctx_frames:left_ctx_frames + center_len].sum()),
            "center_len": center_len,
            "left_ctx": left_ctx_frames,
            "right_ctx": right_ctx_frames,
        })

    # 拼接所有 chunk 的 center 区域
    full_enc = np.concatenate(all_enc_pieces, axis=0)
    full_alphas = np.concatenate(all_alpha_pieces, axis=0)

    # CIF 积分（不加 tail_threshold，模拟 sherpa-onnx 行为）
    acoustic_embeds = cif_integrate(full_enc, full_alphas, threshold=1.0, tail_threshold=None)

    # Decoder
    if acoustic_embeds.shape[0] == 0:
        return "", {"chunks": chunk_details, "total_tokens": 0}

    batch_enc = full_enc[np.newaxis, :, :]
    batch_enc_len = np.array([full_enc.shape[0]], dtype=np.int32)
    batch_ae = acoustic_embeds[np.newaxis, :, :]
    batch_ae_len = np.array([acoustic_embeds.shape[0]], dtype=np.int32)

    feed = {
        "enc": batch_enc,
        "enc_len": batch_enc_len,
        "acoustic_embeds": batch_ae,
        "acoustic_embeds_len": batch_ae_len,
    }
    for i in range(16):
        feed[f"in_cache_{i}"] = np.zeros((1, 512, 10), dtype=np.float32)

    results = dec_sess.run(["sample_ids"], feed)
    token_ids = results[0][0].tolist()
    text = ids_to_text(token_ids, tokens)

    debug = {
        "chunks": chunk_details,
        "total_lfr_frames": T_lfr,
        "total_enc_frames": full_enc.shape[0],
        "alphas_sum": float(full_alphas.sum()),
        "n_tokens": acoustic_embeds.shape[0],
        "token_ids": token_ids,
    }
    return text, debug


def main():
    print("=" * 70)
    print("流式 Chunk 推理截断复现验证")
    print("=" * 70)
    print()

    TEST_CASES = [
        {
            "id": "cs_edge_008",
            "path": FIXTURES / "real" / "codeswitching" / "cs_edge_008.wav",
            "expected_text": "CI pipeline跑了30分钟，还没通过unit test。",
            "tail_keyword": "test",
        },
        {
            "id": "wenet_net_001",
            "path": FIXTURES / "real" / "wenetspeech" / "wenet_net_001.wav",
            "expected_text": "毕业歌会之后，然后我们还去吃个饭，然后就感觉。",
            "tail_keyword": "觉",
        },
    ]

    for case in TEST_CASES:
        if not case["path"].exists():
            print(f"[ERROR] 音频不存在: {case['path']}")
            sys.exit(1)

    # 加载模型
    print("[初始化] 加载 int8 模型...")
    enc_sess = ort.InferenceSession(str(MODEL_DIR / "encoder.int8.onnx"))
    dec_sess = ort.InferenceSession(str(MODEL_DIR / "decoder.int8.onnx"))
    meta = enc_sess.get_modelmeta().custom_metadata_map
    neg_mean = np.array([float(x) for x in meta["neg_mean"].split(",")], dtype=np.float32)
    inv_stddev = np.array([float(x) for x in meta["inv_stddev"].split(",")], dtype=np.float32)
    tokens = load_tokens(MODEL_DIR / "tokens.txt")
    print("  加载完成")
    print()

    for idx, case in enumerate(TEST_CASES, 1):
        cid = case["id"]
        keyword = case["tail_keyword"]
        print(f"[{idx}] {cid}  (关键词: \"{keyword}\")")
        print(f"    期望: {case['expected_text']}")
        print()

        # 模式 A: 流式 + alpha 置零（模拟 sherpa-onnx）
        print("    [A] 流式 chunk + alpha 置零 (sherpa-onnx 行为)...", end=" ", flush=True)
        text_a, dbg_a = streaming_inference(
            enc_sess, dec_sess, tokens, neg_mean, inv_stddev,
            case["path"], zero_right_context=True,
        )
        has_kw_a = keyword.lower() in text_a.lower()
        print("完成")
        print(f"        结果: \"{text_a}\"  {'✓' if has_kw_a else '✗ 截断!'}")
        print(f"        alphas_sum={dbg_a['alphas_sum']:.4f}, n_tokens={dbg_a['n_tokens']}")
        tok_a = [f"{tid}={tokens.get(tid, '?')}" for tid in dbg_a['token_ids']]
        if len(tok_a) > 6:
            print(f"        tail tokens: ...{' '.join(tok_a[-6:])}")
        else:
            print(f"        tail tokens: {' '.join(tok_a)}")
        print(f"        chunks: {len(dbg_a['chunks'])}")
        # 最后一个 chunk 详情
        last = dbg_a["chunks"][-1]
        print(f"        last chunk: center={last['center_range']}, "
              f"alpha_sum_center={last['alpha_sum_center']:.4f}, "
              f"right_ctx={last['right_ctx']}")
        print()

        # 模式 B: 流式 chunk 但 不置零 alpha（消融）
        print("    [B] 流式 chunk + 不置零 alpha (消融对照)...", end=" ", flush=True)
        text_b, dbg_b = streaming_inference(
            enc_sess, dec_sess, tokens, neg_mean, inv_stddev,
            case["path"], zero_right_context=False,
        )
        has_kw_b = keyword.lower() in text_b.lower()
        print("完成")
        print(f"        结果: \"{text_b}\"  {'✓' if has_kw_b else '✗ 截断!'}")
        print(f"        alphas_sum={dbg_b['alphas_sum']:.4f}, n_tokens={dbg_b['n_tokens']}")
        tok_b = [f"{tid}={tokens.get(tid, '?')}" for tid in dbg_b['token_ids']]
        if len(tok_b) > 6:
            print(f"        tail tokens: ...{' '.join(tok_b[-6:])}")
        else:
            print(f"        tail tokens: {' '.join(tok_b)}")
        print()

        # 结论
        if not has_kw_a and has_kw_b:
            print(f"    → 确认: alpha 置零是截断 \"{keyword}\" 的直接原因")
        elif not has_kw_a and not has_kw_b:
            print(f"    → alpha 置零不是唯一原因，chunk 切分本身也导致信息丢失")
        elif has_kw_a and has_kw_b:
            print(f"    → 流式 chunk 推理未截断 \"{keyword}\"（与离线一致）")
        else:
            print(f"    → 异常：alpha 置零反而恢复了 token？")
        print()
        print("-" * 70)
        print()


if __name__ == "__main__":
    main()
