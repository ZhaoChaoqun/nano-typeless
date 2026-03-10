#!/usr/bin/env python3
"""
验证 FunASR is_final 修复 Streaming Paraformer 尾部截断问题。

对比三种模式：
1. sherpa-onnx 流式（基线，已知截断）
2. FunASR 流式 + is_final=True（验证修复）
3. FunASR 流式 + is_final=False（消融对照）

用法:
    uv run --with funasr --with soundfile --with sherpa-onnx \
        python3 scripts/verify_paraformer_tail_fix.py
"""
import os
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

# ── 测试用例 ──────────────────────────────────────────────
FIXTURES = Path(__file__).resolve().parent.parent / "Tests" / "fixtures" / "audio"
MODEL_DIR = Path.home() / "Library" / "Application Support" / "Nano Typeless" / "models" / "sherpa-onnx-streaming-paraformer-bilingual-zh-en"

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


def load_audio(path: Path) -> tuple[np.ndarray, int]:
    """加载音频文件，返回 (float32 samples, sample_rate)。"""
    samples, sr = sf.read(str(path), dtype="float32")
    if len(samples.shape) > 1:
        samples = samples[:, 0]  # stereo → mono
    if sr != 16000:
        raise ValueError(f"需要 16kHz 音频，实际 {sr}Hz: {path}")
    return samples, sr


# ── sherpa-onnx 基线 ──────────────────────────────────────
def run_sherpa_onnx(audio_path: Path) -> str:
    """用 sherpa-onnx 流式识别（复现截断行为）。"""
    import sherpa_onnx

    recognizer = sherpa_onnx.OnlineRecognizer.from_paraformer(
        encoder=str(MODEL_DIR / "encoder.int8.onnx"),
        decoder=str(MODEL_DIR / "decoder.int8.onnx"),
        tokens=str(MODEL_DIR / "tokens.txt"),
    )

    samples, sr = load_audio(audio_path)
    stream = recognizer.create_stream()

    # 分 chunk 送入（600ms = 9600 samples @ 16kHz）
    chunk_size = 9600
    for i in range(0, len(samples), chunk_size):
        chunk = samples[i : i + chunk_size]
        stream.accept_waveform(sr, chunk)
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)

    # 1s 静音 padding
    silence = np.zeros(16000, dtype=np.float32)
    stream.accept_waveform(sr, silence)
    while recognizer.is_ready(stream):
        recognizer.decode_stream(stream)

    stream.input_finished()
    while recognizer.is_ready(stream):
        recognizer.decode_stream(stream)

    result = recognizer.get_result(stream)
    # sherpa-onnx API: result 可能是 str 或有 .text 属性的对象
    text = result.text if hasattr(result, "text") else str(result)
    return text.strip()


# ── FunASR 流式 ──────────────────────────────────────────
def run_funasr_streaming(audio_path: Path, use_is_final: bool) -> str:
    """用 FunASR 流式识别。use_is_final 控制最后一个 chunk 是否传 is_final=True。"""
    from funasr import AutoModel

    model = AutoModel(model="paraformer-zh-streaming", model_revision="v2.0.4")

    chunk_size = [0, 10, 5]  # [左上下文, chunk帧数, 右上下文]
    encoder_chunk_look_back = 4
    decoder_chunk_look_back = 1
    chunk_stride = chunk_size[1] * 960  # 10 * 960 = 9600 samples (600ms)

    samples, sr = load_audio(audio_path)
    total_chunk_num = int(len(samples) - 1) // chunk_stride + 1

    cache = {}
    full_text = ""
    for i in range(total_chunk_num):
        speech_chunk = samples[i * chunk_stride : (i + 1) * chunk_stride]
        is_final = use_is_final and (i == total_chunk_num - 1)
        res = model.generate(
            input=speech_chunk,
            cache=cache,
            is_final=is_final,
            chunk_size=chunk_size,
            encoder_chunk_look_back=encoder_chunk_look_back,
            decoder_chunk_look_back=decoder_chunk_look_back,
        )
        if res and res[0]["text"]:
            full_text += res[0]["text"]

    return full_text.strip()


# ── 主程序 ─────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("Streaming Paraformer 尾部截断修复验证")
    print("=" * 60)
    print()

    # 验证文件存在
    for case in TEST_CASES:
        if not case["path"].exists():
            print(f"[ERROR] 音频不存在: {case['path']}")
            sys.exit(1)
    if not MODEL_DIR.exists():
        print(f"[ERROR] 模型目录不存在: {MODEL_DIR}")
        sys.exit(1)

    results = []
    for idx, case in enumerate(TEST_CASES, 1):
        cid = case["id"]
        keyword = case["tail_keyword"]
        print(f"[{idx}] {cid} (期望含: \"{keyword}\")")
        print(f"    期望文本: {case['expected_text']}")
        print()

        # sherpa-onnx 基线
        print(f"    运行 sherpa-onnx ...", end=" ", flush=True)
        text_sherpa = run_sherpa_onnx(case["path"])
        has_kw_sherpa = keyword.lower() in text_sherpa.lower()
        mark_sherpa = "✓" if has_kw_sherpa else "✗"
        print(f"完成")
        print(f"    sherpa-onnx:             \"{text_sherpa}\"  {mark_sherpa}")

        # FunASR is_final=True
        print(f"    运行 FunASR (is_final=True) ...", end=" ", flush=True)
        text_funasr_final = run_funasr_streaming(case["path"], use_is_final=True)
        has_kw_final = keyword.lower() in text_funasr_final.lower()
        mark_final = "✓ 恢复" if has_kw_final else "✗ 截断"
        print(f"完成")
        print(f"    FunASR (is_final=True):  \"{text_funasr_final}\"  ← {mark_final}")

        # FunASR is_final=False（消融）
        print(f"    运行 FunASR (is_final=False) ...", end=" ", flush=True)
        text_funasr_no_final = run_funasr_streaming(case["path"], use_is_final=False)
        has_kw_no_final = keyword.lower() in text_funasr_no_final.lower()
        mark_no_final = "✓" if has_kw_no_final else "✗ 截断"
        print(f"完成")
        print(f"    FunASR (is_final=False): \"{text_funasr_no_final}\"  ← {mark_no_final}")
        print()

        results.append({
            "id": cid,
            "keyword": keyword,
            "sherpa": has_kw_sherpa,
            "funasr_final": has_kw_final,
            "funasr_no_final": has_kw_no_final,
        })

    # 汇总
    print("=" * 60)
    print("汇总")
    print("=" * 60)
    print(f"{'ID':<20} {'关键词':<15} {'sherpa-onnx':<12} {'FunASR final':<14} {'FunASR no-final'}")
    print("-" * 75)
    for r in results:
        s = "✓" if r["sherpa"] else "✗"
        f = "✓" if r["funasr_final"] else "✗"
        n = "✓" if r["funasr_no_final"] else "✗"
        print(f"{r['id']:<20} {r['keyword']:<15} {s:<12} {f:<14} {n}")
    print()

    fixed_count = sum(1 for r in results if r["funasr_final"] and not r["sherpa"])
    if fixed_count > 0:
        print(f"结论: FunASR is_final=True 成功恢复 {fixed_count}/{len(results)} 条截断 token")
        print("       → sherpa-onnx 缺失 is_final 机制是根因")
    else:
        all_same = all(r["funasr_final"] == r["sherpa"] for r in results)
        if all_same:
            print("结论: FunASR is_final=True 未恢复任何 token，问题可能在更底层")
        else:
            print("结论: 混合结果，需进一步分析")


if __name__ == "__main__":
    main()
