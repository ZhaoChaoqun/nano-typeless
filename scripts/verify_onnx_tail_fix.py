#!/usr/bin/env python3
"""
用原生 ONNX Runtime 验证 Streaming Paraformer 尾部截断修复。

对比不同精度 encoder (int8/fp32) 在 CIF tail_threshold 下的表现，
验证 int8 量化精度损失是否导致尾部 token 丢失。

用法:
    cd ~/Github/typeless
    uv run --with onnxruntime --with kaldi-native-fbank --with soundfile \
        python3 scripts/verify_onnx_tail_fix.py
"""
import math
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

# ── 路径 ──────────────────────────────────────────────────
MODEL_DIR = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Nano Typeless"
    / "models"
    / "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
)
FP32_DIR = Path("/tmp/paraformer-fp32")
FIXTURES = Path(__file__).resolve().parent.parent / "Tests" / "fixtures" / "audio"

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
    {
        "id": "ascend_cs_003",
        "path": FIXTURES / "real" / "ascend" / "ascend_cs_003.wav",
        "expected_text": "深圳啊，或者是上海这种比较大的城市，会有更多opportunity。",
        "tail_keyword": "opportunity",
    },
]


# ── 1. 音频加载 ──────────────────────────────────────────
def load_audio(path: Path) -> tuple[np.ndarray, int]:
    """加载 WAV → float32 samples（int16 range: ×32768）。"""
    samples, sr = sf.read(str(path), dtype="float32")
    if len(samples.shape) > 1:
        samples = samples[:, 0]
    if sr != 16000:
        raise ValueError(f"需要 16kHz，实际 {sr}Hz: {path}")
    # sherpa-onnx 不做 normalize_samples，期望 int16 范围
    samples = samples * 32768.0
    return samples, sr


# ── 2. Fbank 特征提取 ────────────────────────────────────
def extract_fbank(samples: np.ndarray, sr: int = 16000) -> np.ndarray:
    """用 kaldi-native-fbank 提取 80-dim log-mel fbank。返回 [T, 80]。"""
    import kaldi_native_fbank as knf

    opts = knf.FbankOptions()
    opts.frame_opts.samp_freq = sr
    opts.frame_opts.frame_length_ms = 25.0
    opts.frame_opts.frame_shift_ms = 10.0
    opts.frame_opts.window_type = "hamming"
    opts.frame_opts.dither = 0.0
    opts.frame_opts.snip_edges = True
    opts.mel_opts.num_bins = 80
    opts.energy_floor = 0.0

    fbank = knf.OnlineFbank(opts)
    fbank.accept_waveform(sr, samples.tolist())
    fbank.input_finished()

    num_frames = fbank.num_frames_ready
    feats = np.zeros((num_frames, 80), dtype=np.float32)
    for i in range(num_frames):
        feats[i] = fbank.get_frame(i)

    return feats


# ── 3. LFR 变换 ──────────────────────────────────────────
def apply_lfr(feats: np.ndarray, m: int = 7, n: int = 6) -> np.ndarray:
    """Low Frame Rate: 拼 m 帧步长 n。返回 [T_lfr, 80*m]。"""
    T, D = feats.shape
    # 左 padding: 复制首帧 (m-1)//2 次
    pad_left = (m - 1) // 2  # = 3
    padded = np.concatenate([np.tile(feats[0:1], (pad_left, 1)), feats], axis=0)
    T_padded = padded.shape[0]
    # 计算 LFR 帧数
    T_lfr = (T_padded - m) // n + 1
    lfr_feats = np.zeros((T_lfr, D * m), dtype=np.float32)
    for i in range(T_lfr):
        start = i * n
        lfr_feats[i] = padded[start : start + m].reshape(-1)
    return lfr_feats


# ── 4. CMVN ──────────────────────────────────────────────
def apply_cmvn(
    feats: np.ndarray, neg_mean: np.ndarray, inv_stddev: np.ndarray
) -> np.ndarray:
    """CMVN: (feats + neg_mean) * inv_stddev。"""
    return (feats + neg_mean) * inv_stddev


# ── 5. Positional Encoding ───────────────────────────────
def apply_pe(feats: np.ndarray, d_model: int, offset: int = 0) -> np.ndarray:
    """Sinusoidal positional encoding（与 sherpa-onnx C++ 一致）。"""
    T, D = feats.shape
    pe = np.zeros((T, d_model), dtype=np.float32)
    log_scale = -math.log(10000.0) / (d_model - 1)
    for t in range(T):
        pos = t + 1 + offset  # sherpa-onnx 用 1-based position
        for d in range(0, d_model, 2):
            inv_timescale = pos * math.exp(d * log_scale)
            pe[t, d] = math.sin(inv_timescale)
            if d + 1 < d_model:
                pe[t, d + 1] = math.cos(inv_timescale)
    # PE 只加到前 d_model 维，如果 D > d_model 则剩余部分不加
    feats[:, :d_model] += pe[:, :d_model]
    return feats


# ── 6. CIF 积分 ──────────────────────────────────────────
def cif_integrate(
    enc: np.ndarray,
    alphas: np.ndarray,
    threshold: float = 1.0,
    tail_threshold: float | None = None,
) -> np.ndarray:
    """
    CIF (Continuous Integrate-and-Fire) 积分。

    enc: [T, D]  encoder hidden states
    alphas: [T]  CIF alpha weights
    threshold: fire threshold (default 1.0)
    tail_threshold: 如果非 None，在末尾追加此 alpha 值强制 flush
    返回: acoustic_embeds [N_tokens, D]
    """
    T, D = enc.shape
    alpha_list = alphas.tolist()
    enc_list = enc

    # 如果需要 tail flush，追加一个零 hidden + tail_threshold alpha
    if tail_threshold is not None:
        alpha_list = alpha_list + [tail_threshold]
        enc_list = np.concatenate([enc_list, np.zeros((1, D), dtype=np.float32)], axis=0)
        T += 1

    embeds = []
    accumulate = 0.0
    hidden_buf = np.zeros(D, dtype=np.float32)

    for t in range(T):
        alpha = alpha_list[t]
        accumulate += alpha
        hidden_buf += alpha * enc_list[t]

        if accumulate >= threshold:
            # fire: 当前帧的部分贡献归到本 token，剩余开始下一个
            remainder = accumulate - threshold
            # 从 hidden_buf 中减去多算的部分
            embed = hidden_buf - remainder * enc_list[t]
            embeds.append(embed.copy())

            # 新 token 从 remainder 开始
            accumulate = remainder
            hidden_buf = remainder * enc_list[t].copy()

    if len(embeds) == 0:
        return np.zeros((0, D), dtype=np.float32)

    return np.stack(embeds, axis=0)


# ── 7. Token ID → 文本 ───────────────────────────────────
def load_tokens(path: Path) -> dict[int, str]:
    """加载 tokens.txt → {id: token}。"""
    tokens = {}
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                token = parts[0]
                idx = int(parts[1])
                tokens[idx] = token
    return tokens


def ids_to_text(token_ids: list[int], tokens: dict[int, str]) -> str:
    """将 token IDs 转为文本，处理 BPE @@ 连接。"""
    result = []
    for tid in token_ids:
        if tid in (0, 1, 2):  # <blank>, <s>, </s>
            continue
        tok = tokens.get(tid, f"<{tid}>")
        if tok == "<unk>":
            continue
        if tok.endswith("@@"):
            result.append(tok[:-2])  # 去掉 @@ 后缀，不加空格
        else:
            result.append(tok)
    return "".join(result)


# ── 8. ONNX 推理 ─────────────────────────────────────────
class ParaformerONNX:
    def __init__(self, model_dir: Path, encoder_path: str | None = None, decoder_path: str | None = None, label: str = "", disable_all_opt: bool = False):
        self.model_dir = model_dir
        self.label = label

        sess_opts = ort.SessionOptions()
        if disable_all_opt:
            sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED

        # 加载 encoder（支持自定义路径）
        enc_path = encoder_path or str(model_dir / "encoder.int8.onnx")
        self.enc_sess = ort.InferenceSession(enc_path, sess_opts)

        # 从 metadata 读取参数（所有精度的 encoder 都有相同的 metadata）
        meta = self.enc_sess.get_modelmeta().custom_metadata_map
        self.neg_mean = np.array(
            [float(x) for x in meta["neg_mean"].split(",")], dtype=np.float32
        )
        self.inv_stddev = np.array(
            [float(x) for x in meta["inv_stddev"].split(",")], dtype=np.float32
        )
        self.lfr_m = int(meta["lfr_window_size"])
        self.lfr_n = int(meta["lfr_window_shift"])
        self.enc_dim = int(meta["encoder_output_size"])

        # 加载 decoder（支持自定义路径）
        dec_path = decoder_path or str(model_dir / "decoder.int8.onnx")
        self.dec_sess = ort.InferenceSession(dec_path, sess_opts)

        # 加载 tokens
        self.tokens = load_tokens(model_dir / "tokens.txt")

        enc_name = Path(enc_path).name
        dec_name = Path(dec_path).name
        print(f"  [{label}] 加载完成: encoder={enc_name}, decoder={dec_name}")
        print(f"    enc_dim={self.enc_dim}, lfr={self.lfr_m}/{self.lfr_n}, vocab={len(self.tokens)}")

    def extract_features(self, samples: np.ndarray, sr: int = 16000) -> np.ndarray:
        """wav → fbank → LFR → CMVN → [T_lfr, 560]"""
        fbank = extract_fbank(samples, sr)
        lfr = apply_lfr(fbank, self.lfr_m, self.lfr_n)
        cmvn = apply_cmvn(lfr, self.neg_mean, self.inv_stddev)
        return cmvn

    def encode(self, features: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Encoder forward: features [T, 560] → (enc [T, 512], alphas [T])"""
        speech = features[np.newaxis, :, :]  # [1, T, 560]
        speech_lengths = np.array([features.shape[0]], dtype=np.int32)

        enc, enc_len, alphas = self.enc_sess.run(
            ["enc", "enc_len", "alphas"],
            {"speech": speech, "speech_lengths": speech_lengths},
        )
        # enc: [1, T, 512], alphas: [1, T]
        return enc[0], alphas[0]

    def decode(
        self, enc: np.ndarray, enc_len: int, acoustic_embeds: np.ndarray
    ) -> list[int]:
        """Decoder forward → token IDs。"""
        if acoustic_embeds.shape[0] == 0:
            return []

        batch_enc = enc[np.newaxis, :, :]  # [1, T, 512]
        batch_enc_len = np.array([enc_len], dtype=np.int32)
        batch_ae = acoustic_embeds[np.newaxis, :, :]  # [1, N_tok, 512]
        batch_ae_len = np.array([acoustic_embeds.shape[0]], dtype=np.int32)

        # 初始化 16 层 decoder cache
        feed = {
            "enc": batch_enc,
            "enc_len": batch_enc_len,
            "acoustic_embeds": batch_ae,
            "acoustic_embeds_len": batch_ae_len,
        }
        for i in range(16):
            feed[f"in_cache_{i}"] = np.zeros((1, 512, 10), dtype=np.float32)

        results = self.dec_sess.run(["sample_ids"], feed)
        sample_ids = results[0][0]  # [N_tok]
        return sample_ids.tolist()

    def transcribe(
        self, audio_path: Path, tail_threshold: float | None = None
    ) -> tuple[str, dict]:
        """完整的 ASR pipeline。返回 (文本, debug_info)。"""
        samples, sr = load_audio(audio_path)
        features = self.extract_features(samples, sr)

        enc, alphas = self.encode(features)

        # CIF 积分
        acoustic_embeds = cif_integrate(
            enc, alphas, threshold=1.0, tail_threshold=tail_threshold
        )

        # Decoder
        token_ids = self.decode(enc, enc.shape[0], acoustic_embeds)
        text = ids_to_text(token_ids, self.tokens)

        debug = {
            "fbank_frames": features.shape[0],
            "enc_frames": enc.shape[0],
            "alphas_sum": float(alphas.sum()),
            "alphas_last10": alphas[-10:].tolist() if len(alphas) >= 10 else alphas.tolist(),
            "n_tokens": acoustic_embeds.shape[0],
            "token_ids": token_ids,  # 全部
        }
        return text, debug


# ── 主程序 ─────────────────────────────────────────────────
def run_single(model: ParaformerONNX, case: dict) -> dict:
    """对单条音频运行有/无 tail_threshold 两种模式。"""
    keyword = case["tail_keyword"]

    # 无 tail fix
    text_no, dbg_no = model.transcribe(case["path"], tail_threshold=None)
    has_kw_no = keyword.lower() in text_no.lower()

    # 有 tail fix
    text_fix, dbg_fix = model.transcribe(case["path"], tail_threshold=0.45)
    has_kw_fix = keyword.lower() in text_fix.lower()

    return {
        "text_no_fix": text_no,
        "text_with_fix": text_fix,
        "has_kw_no": has_kw_no,
        "has_kw_fix": has_kw_fix,
        "dbg_no": dbg_no,
        "dbg_fix": dbg_fix,
    }


def main():
    print("=" * 70)
    print("原生 ONNX Runtime — int8 vs fp32 Encoder 精度对比")
    print("=" * 70)
    print()

    # 验证音频文件
    for case in TEST_CASES:
        if not case["path"].exists():
            print(f"[ERROR] 音频不存在: {case['path']}")
            sys.exit(1)

    # 构建模型配置
    configs = []

    # int8 encoder + int8 decoder（原始 sherpa-onnx 模型）
    configs.append({
        "label": "int8",
        "encoder": str(MODEL_DIR / "encoder.int8.onnx"),
        "decoder": str(MODEL_DIR / "decoder.int8.onnx"),
    })

    # fp32 encoder + int8 decoder（仅替换 encoder）
    fp32_enc = FP32_DIR / "encoder.onnx"
    if fp32_enc.exists():
        configs.append({
            "label": "fp32-enc",
            "encoder": str(fp32_enc),
            "decoder": str(MODEL_DIR / "decoder.int8.onnx"),
        })

    # fp32 encoder + fp32 decoder（全 fp32）
    fp32_dec = FP32_DIR / "decoder.onnx"
    if fp32_dec.exists():
        configs.append({
            "label": "fp32-all",
            "encoder": str(fp32_enc),
            "decoder": str(fp32_dec),
        })

    # fp16 encoder + fp16 decoder（全 fp16，需要降级图优化）
    fp16_enc = FP32_DIR / "encoder.fp16.ort.onnx"
    fp16_dec = FP32_DIR / "decoder.fp16.onnx"
    if fp16_enc.exists() and fp16_dec.exists():
        configs.append({
            "label": "fp16-all",
            "encoder": str(fp16_enc),
            "decoder": str(fp16_dec),
            "disable_all_opt": True,
        })

    if len(configs) == 1:
        print("[WARN] 未找到 fp32 模型，仅运行 int8 对比")
        print(f"  期望路径: {FP32_DIR}")
        print()

    # 加载模型
    print("[初始化] 加载模型...")
    models = {}
    for cfg in configs:
        models[cfg["label"]] = ParaformerONNX(
            MODEL_DIR,
            encoder_path=cfg["encoder"],
            decoder_path=cfg["decoder"],
            label=cfg["label"],
            disable_all_opt=cfg.get("disable_all_opt", False),
        )
    print()

    # 运行测试
    all_results = {}  # {case_id: {model_label: result}}
    for idx, case in enumerate(TEST_CASES, 1):
        cid = case["id"]
        keyword = case["tail_keyword"]
        print(f"[{idx}] {cid}  (关键词: \"{keyword}\")")
        print(f"    期望: {case['expected_text']}")
        print()

        all_results[cid] = {}
        for label, model in models.items():
            print(f"    [{label}] 运行中...", end=" ", flush=True)
            result = run_single(model, case)
            all_results[cid][label] = result

            mark_no = "✓" if result["has_kw_no"] else "✗"
            mark_fix = "✓" if result["has_kw_fix"] else "✗"
            print("完成")
            print(f"      无 tail_fix:  \"{result['text_no_fix']}\"  {mark_no}")
            print(f"      有 tail_fix:  \"{result['text_with_fix']}\"  {mark_fix}")

            # token 详情
            tok_no = [f"{tid}={model.tokens.get(tid, '?')}" for tid in result["dbg_no"]["token_ids"]]
            tok_fix = [f"{tid}={model.tokens.get(tid, '?')}" for tid in result["dbg_fix"]["token_ids"]]
            print(f"      alphas_sum={result['dbg_no']['alphas_sum']:.4f}, "
                  f"n_tok(no/fix)={result['dbg_no']['n_tokens']}/{result['dbg_fix']['n_tokens']}")
            # 只显示最后 5 个 token（关注尾部差异）
            if len(tok_no) > 5:
                print(f"      tail tokens (no_fix):  ...{' '.join(tok_no[-5:])}")
            else:
                print(f"      tail tokens (no_fix):  {' '.join(tok_no)}")
            if len(tok_fix) > 5:
                print(f"      tail tokens (fix):     ...{' '.join(tok_fix[-5:])}")
            else:
                print(f"      tail tokens (fix):     {' '.join(tok_fix)}")
            print()

    # ── 汇总表格 ──────────────────────────────────────────
    print("=" * 70)
    print("汇总")
    print("=" * 70)
    labels = [cfg["label"] for cfg in configs]

    # 表头
    header = f"{'ID':<18} {'关键词':<14}"
    for label in labels:
        header += f" {label+' (no/fix)':<18}"
    print(header)
    print("-" * len(header))

    for case in TEST_CASES:
        cid = case["id"]
        keyword = case["tail_keyword"]
        row = f"{cid:<18} {keyword:<14}"
        for label in labels:
            r = all_results[cid][label]
            n = "✓" if r["has_kw_no"] else "✗"
            f = "✓" if r["has_kw_fix"] else "✗"
            row += f" {n + '/' + f:<18}"
        print(row)
    print()

    # 分析
    print("分析:")
    for case in TEST_CASES:
        cid = case["id"]
        keyword = case["tail_keyword"]
        int8_r = all_results[cid].get("int8", {})
        fp32_enc_r = all_results[cid].get("fp32-enc", {})
        fp32_all_r = all_results[cid].get("fp32-all", {})

        int8_ok = int8_r.get("has_kw_no", False) or int8_r.get("has_kw_fix", False)
        fp32_ok = fp32_enc_r.get("has_kw_no", False) or fp32_enc_r.get("has_kw_fix", False)

        if int8_ok and fp32_ok:
            print(f"  [{cid}] int8 和 fp32 都能恢复 \"{keyword}\" — 截断来自流式 chunk 调度")
        elif not int8_ok and fp32_ok:
            print(f"  [{cid}] fp32 能恢复 \"{keyword}\" 但 int8 不能 — int8 量化精度损失是根因")
            # 比较 alphas_sum 差异
            int8_alpha = int8_r.get("dbg_no", {}).get("alphas_sum", 0)
            fp32_alpha = fp32_enc_r.get("dbg_no", {}).get("alphas_sum", 0)
            print(f"         alphas_sum: int8={int8_alpha:.4f}, fp32={fp32_alpha:.4f}, "
                  f"delta={abs(int8_alpha - fp32_alpha):.4f}")
        elif not int8_ok and not fp32_ok:
            print(f"  [{cid}] 两者都无法恢复 \"{keyword}\" — encoder 层面信息丢失")
        else:
            print(f"  [{cid}] int8 能恢复但 fp32 不能（异常情况）")

    # 结论
    if "fp32-enc" in models:
        int8_only_fail = sum(
            1 for case in TEST_CASES
            if not (all_results[case["id"]]["int8"]["has_kw_no"] or all_results[case["id"]]["int8"]["has_kw_fix"])
            and (all_results[case["id"]]["fp32-enc"]["has_kw_no"] or all_results[case["id"]]["fp32-enc"]["has_kw_fix"])
        )
        if int8_only_fail > 0:
            print()
            print(f"结论: {int8_only_fail}/{len(TEST_CASES)} 条因 int8 量化精度损失丢失尾部 token")
            print("  → 使用 fp32 或 fp16 encoder 可修复")
            # 模型大小对比
            print()
            print("模型大小对比:")
            for cfg in configs:
                enc_size = Path(cfg["encoder"]).stat().st_size / 1024 / 1024
                dec_size = Path(cfg["decoder"]).stat().st_size / 1024 / 1024
                total = enc_size + dec_size
                print(f"  {cfg['label']:<12} encoder={enc_size:>6.0f}MB  decoder={dec_size:>6.0f}MB  total={total:>6.0f}MB")


if __name__ == "__main__":
    main()
