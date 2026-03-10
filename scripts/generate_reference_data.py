#!/usr/bin/env python3
"""
生成 Paraformer 各环节参考数据（.npy），用于与 Swift 实现逐环节对齐验证。

对一条测试音频运行完整离线 pipeline，在每个环节导出中间结果。
Swift XCTest 加载这些 .npy 文件并与 ParaformerONNX.swift 的输出对比。

用法:
    cd ~/Github/typeless
    uv run --with onnxruntime --with kaldi-native-fbank --with soundfile \
        python3 scripts/generate_reference_data.py

可选参数:
    --audio      测试音频路径 (默认: cs_edge_008.wav)
    --model-dir  模型目录 (默认: fp16 模型)
    --encoder    encoder 文件名 (默认: encoder.fp16.onnx)
    --decoder    decoder 文件名 (默认: decoder.fp16.onnx)
    --output-dir 输出目录 (默认: Tests/fixtures/alignment/)
"""
import argparse
import sys
from pathlib import Path

import numpy as np

# 复用 verify_onnx_tail_fix.py 中的函数
sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_onnx_tail_fix import (
    load_audio,
    extract_fbank,
    apply_lfr,
    apply_cmvn,
    cif_integrate,
    ids_to_text,
    load_tokens,
)

import onnxruntime as ort


def main():
    parser = argparse.ArgumentParser(description="生成 Paraformer 各环节参考数据")
    parser.add_argument(
        "--audio",
        default=str(
            Path(__file__).resolve().parent.parent
            / "Tests/fixtures/audio/real/codeswitching/cs_edge_008.wav"
        ),
        help="测试音频路径",
    )
    parser.add_argument(
        "--model-dir",
        default=str(
            Path.home()
            / "Library/Application Support/Nano Typeless/models"
            / "sherpa-onnx-streaming-paraformer-bilingual-zh-en-fp16"
        ),
        help="模型目录",
    )
    parser.add_argument("--encoder", default="encoder.fp16.onnx", help="encoder 文件名")
    parser.add_argument("--decoder", default="decoder.fp16.onnx", help="decoder 文件名")
    parser.add_argument(
        "--output-dir",
        default=str(
            Path(__file__).resolve().parent.parent / "Tests/fixtures/alignment"
        ),
        help="输出目录",
    )
    args = parser.parse_args()

    model_dir = Path(args.model_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    audio_path = Path(args.audio)
    enc_path = model_dir / args.encoder
    dec_path = model_dir / args.decoder
    tokens_path = model_dir / "tokens.txt"

    # 验证文件存在
    for p, name in [
        (audio_path, "音频"),
        (enc_path, "Encoder"),
        (dec_path, "Decoder"),
        (tokens_path, "Tokens"),
    ]:
        if not p.exists():
            print(f"[ERROR] {name}文件不存在: {p}")
            sys.exit(1)

    print("=" * 60)
    print("Paraformer 参考数据生成")
    print("=" * 60)
    print(f"  音频:    {audio_path.name}")
    print(f"  Encoder: {enc_path.name}")
    print(f"  Decoder: {dec_path.name}")
    print(f"  输出:    {output_dir}")
    print()

    # ── Stage 1: 音频加载 ──
    print("[1/7] 加载音频...")
    samples, sr = load_audio(audio_path)
    np.save(output_dir / "ref_samples.npy", samples)
    print(f"  samples: shape={samples.shape}, range=[{samples.min():.1f}, {samples.max():.1f}]")

    # ── Stage 2: Fbank ──
    print("[2/7] 提取 Fbank...")
    fbank = extract_fbank(samples, sr)
    np.save(output_dir / "ref_fbank.npy", fbank)
    print(f"  fbank: shape={fbank.shape}")

    # ── Stage 3: LFR ──
    print("[3/7] LFR 变换...")
    # 从 encoder metadata 读取 LFR 参数
    sess_opts = ort.SessionOptions()
    sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED
    enc_sess = ort.InferenceSession(str(enc_path), sess_opts)
    meta = enc_sess.get_modelmeta().custom_metadata_map
    lfr_m = int(meta["lfr_window_size"])
    lfr_n = int(meta["lfr_window_shift"])
    enc_dim = int(meta["encoder_output_size"])

    lfr = apply_lfr(fbank, lfr_m, lfr_n)
    np.save(output_dir / "ref_lfr.npy", lfr)
    print(f"  lfr: shape={lfr.shape}, lfr_m={lfr_m}, lfr_n={lfr_n}")

    # ── Stage 4: CMVN ──
    print("[4/7] CMVN 归一化...")
    neg_mean = np.array(
        [float(x) for x in meta["neg_mean"].split(",")], dtype=np.float32
    )
    inv_stddev = np.array(
        [float(x) for x in meta["inv_stddev"].split(",")], dtype=np.float32
    )
    np.save(output_dir / "ref_neg_mean.npy", neg_mean)
    np.save(output_dir / "ref_inv_stddev.npy", inv_stddev)

    cmvn = apply_cmvn(lfr, neg_mean, inv_stddev)
    np.save(output_dir / "ref_cmvn.npy", cmvn)
    print(f"  cmvn: shape={cmvn.shape}")

    # ── Stage 5: Encoder ──
    print("[5/7] Encoder forward...")
    speech = cmvn[np.newaxis, :, :]  # [1, T, 560]
    speech_lengths = np.array([cmvn.shape[0]], dtype=np.int32)

    enc, enc_len, alphas = enc_sess.run(
        ["enc", "enc_len", "alphas"],
        {"speech": speech, "speech_lengths": speech_lengths},
    )
    enc = enc[0]       # [T, 512]
    alphas = alphas[0]  # [T]

    np.save(output_dir / "ref_enc.npy", enc)
    np.save(output_dir / "ref_alphas.npy", alphas)
    print(f"  enc: shape={enc.shape}, alphas: shape={alphas.shape}")
    print(f"  alphas_sum={alphas.sum():.4f}")

    # ── Stage 6: CIF 积分 ──
    print("[6/7] CIF 积分 (tail_threshold=0.45)...")
    acoustic_embeds = cif_integrate(enc, alphas, threshold=1.0, tail_threshold=0.45)
    np.save(output_dir / "ref_acoustic_embeds.npy", acoustic_embeds)
    print(f"  acoustic_embeds: shape={acoustic_embeds.shape}")

    # ── Stage 7: Decoder ──
    print("[7/7] Decoder forward...")
    dec_sess = ort.InferenceSession(str(dec_path), sess_opts)
    tokens = load_tokens(tokens_path)

    if acoustic_embeds.shape[0] == 0:
        token_ids = []
        text = ""
    else:
        batch_enc = enc[np.newaxis, :, :]  # [1, T, 512]
        batch_enc_len = np.array([enc.shape[0]], dtype=np.int32)
        batch_ae = acoustic_embeds[np.newaxis, :, :]  # [1, N_tok, 512]
        batch_ae_len = np.array([acoustic_embeds.shape[0]], dtype=np.int32)

        feed = {
            "enc": batch_enc,
            "enc_len": batch_enc_len,
            "acoustic_embeds": batch_ae,
            "acoustic_embeds_len": batch_ae_len,
        }
        for i in range(16):
            feed[f"in_cache_{i}"] = np.zeros((1, enc_dim, 10), dtype=np.float32)

        results = dec_sess.run(["sample_ids"], feed)
        sample_ids = results[0][0]  # [N_tok]
        token_ids = sample_ids.tolist()
        text = ids_to_text(token_ids, tokens)

    np.save(output_dir / "ref_token_ids.npy", np.array(token_ids, dtype=np.int32))
    (output_dir / "ref_text.txt").write_text(text, encoding="utf-8")

    print(f"  token_ids: {len(token_ids)} tokens")
    print(f"  text: \"{text}\"")

    # ── 汇总 ──
    print()
    print("=" * 60)
    print("参考数据生成完成")
    print("=" * 60)
    files = sorted(output_dir.glob("ref_*"))
    for f in files:
        size = f.stat().st_size
        if size > 1024 * 1024:
            size_str = f"{size / 1024 / 1024:.1f} MB"
        elif size > 1024:
            size_str = f"{size / 1024:.1f} KB"
        else:
            size_str = f"{size} B"
        print(f"  {f.name:<30s}  {size_str:>10s}")


if __name__ == "__main__":
    main()
