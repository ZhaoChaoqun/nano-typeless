# ASR Pipeline Benchmark 使用指南

Swift XCTest benchmark，直接复用产品代码评估 4 个 ASR Pipeline。

## Pipeline

| # | Pipeline | 说明 |
|---|----------|------|
| 1 | Qwen3-ASR (离线) | pushAudio(finalize:true) 一次性识别 |
| 2 | Qwen3-ASR (流式) | chunk+rollback 模拟流式 |
| 3 | Paraformer Pipeline | Streaming Paraformer + ITN → CSC → CT-Transformer 标点 |
| 4 | FunASR Nano LLM | SenseVoice encoder + Qwen3 LLM 离线识别（自带标点） |

## 运行完整 Benchmark

```bash
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests
```

运行完成后报告自动保存到 `docs/benchmark-report-swift.md`。

## 运行单个 Pipeline

```bash
# Qwen3-ASR 离线
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testQwenASROfflinePipeline

# Qwen3-ASR 流式
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testQwenASRStreamPipeline

# Paraformer Pipeline
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testParaformerPipeline

# FunASR Nano LLM
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testFunASRNanoLLMPipeline
```

## 筛选特定 Entry

通过写入 `/tmp/benchmark_entry_filter.txt` 文件来筛选条目（逗号分隔多个 ID）：

```bash
# 只跑单个 entry
echo "ascend_cs_003" > /tmp/benchmark_entry_filter.txt
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testParaformerPipeline

# 跑多个 entry
echo "ascend_cs_003,zh_short_01,mixed_02" > /tmp/benchmark_entry_filter.txt
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testFunASRNanoLLMPipeline

# 单个 entry + 所有 pipeline
echo "ascend_cs_003" > /tmp/benchmark_entry_filter.txt
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
  -only-testing:TypelessTests/ASRPipelineBenchmarkTests

# 清除筛选（恢复全量运行）
rm /tmp/benchmark_entry_filter.txt
```

## 查看日志

`print()` 输出会被 xcodebuild 吞掉，详细日志自动写入临时文件：

```bash
# 查看最新日志
ls -lt /private/var/folders/*/*/T/benchmark_swift_*.log | head -1
# 或
find /private/var/folders -name "benchmark_swift_*.log" 2>/dev/null | sort | tail -1 | xargs cat
```

## Entry ID 列表

可用的 entry ID 来自 `tests/fixtures/corpus.json` 和 `tests/fixtures/real_manifest.json`。查看所有可用 ID：

```bash
python3 -c "
import json
for f in ['tests/fixtures/corpus.json', 'tests/fixtures/real_manifest.json']:
    data = json.load(open(f))
    for e in data: print(e['id'])
"
```
