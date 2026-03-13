# 测试语料维护指南

本文档介绍 Typeless 项目的 ASR 测试语料体系，包括语料结构、生成流程和日常维护方法。

---

## 概览

项目使用**两套互补的测试语料**评估 ASR 识别质量：

| | 合成语料 (`synthetic_manifest.json`) | 录制语料 (`recorded_manifest.json`) |
|---|---|---|
| **定位** | 可控场景覆盖（"出题考试"） | 真实世界验证（"实战检验"） |
| **音频来源** | Edge-TTS 机器合成 + 程序合成静音/噪声 | AISHELL、ASCEND 等开源数据集的真人录音 |
| **条目数** | ~160 条 | ~30 条 |
| **定义文件** | `scripts/synthetic_corpus.yaml` | `scripts/download_recorded_corpus.py` |
| **生成脚本** | `scripts/generate_synthetic_corpus.py` | `scripts/download_recorded_corpus.py` |
| **输出位置** | `Tests/fixtures/synthetic_manifest.json` | `Tests/fixtures/recorded_manifest.json` |

两份语料在 Benchmark 测试中被合并加载，全面评估识别准确度。

---

## 目录结构

```
Tests/fixtures/
├── synthetic_manifest.json         # 合成语料元数据（脚本生成，勿手动编辑）
├── recorded_manifest.json          # 录制语料元数据（脚本生成）
└── audio/
    ├── synthetic/                  # 所有合成音频（Edge-TTS + 静音/噪声）~160 个 WAV
    └── recorded/                   # 真实录音（需运行下载脚本获取）
        ├── aishell/                #   AISHELL-1 标准普通话
        ├── minds14/                #   MINDS-14 对话录音
        ├── ascend/                 #   ASCEND 中英代码切换
        └── wenetspeech/            #   WenetSpeech 多场景（需 HuggingFace 授权）

scripts/
├── synthetic_corpus.yaml           # 合成语料定义（人工维护的源头）
├── generate_synthetic_corpus.py    # 合成语料生成脚本
└── download_recorded_corpus.py     # 录制语料下载脚本
```

---

## 语料条目格式

两份 JSON 使用**完全相同的条目结构**，Swift 端通过同一个 `CorpusEntry` 解码：

```json
{
  "id": "mixed_02",
  "category": "mixed_technical",
  "expected_text": ["MacBook Pro M3芯片性能提升了百分之40。", "MacBook Pro M3芯片性能提升了40%。"],
  "match_mode": "contains_all",
  "match_keywords": ["MacBook", "芯片"],
  "audio_files": { "synthetic": "audio/synthetic/mixed_02.wav" },
  "duration_sec": 4.52,
  "language": "zh"
}
```

### 字段说明

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 唯一标识符 |
| `category` | string | 是 | 分类标签，用于测试报告分组 |
| `expected_text` | string 或 [string] | 是 | 期望识别结果。数组表示多个可接受的变体（取最小 CER） |
| `match_mode` | string | 是 | 匹配策略，见下表 |
| `audio_files` | {string: string} | 是 | 音频源映射，key 为来源类型（`"synthetic"` 或 `"recorded"`），value 为相对路径 |
| `duration_sec` | number | 是 | 音频时长（秒） |
| `language` | string | 是 | 语言：`zh` / `en` / `mixed` / `none` |
| `match_keywords` | [string] | 否 | `contains_all` 模式下的关键词列表 |
| `match_threshold` | number | 否 | `character_error_rate` 模式下的 CER 阈值（默认 0.15） |

### 匹配模式

| `match_mode` | 用途 | 判定逻辑 |
|---|---|---|
| `character_error_rate` | 精确评估 | CER ≤ `match_threshold`（默认 0.15）则通过 |
| `contains_all` | 关键词覆盖 | 识别结果包含所有 `match_keywords` 则通过 |
| `contains` | 宽松匹配 | 识别结果包含任一关键词则通过 |
| `empty_or_whitespace` | 静音检测 | 识别结果为空或纯空白则通过 |

### expected_text 多备选

当 ASR 输出可能有多种合理格式时（如数字 vs 中文数字），使用数组：

```yaml
expected_text:
  - "投资ROI达到了百分之二十。"    # 中文数字写法
  - "投资ROI达到了20%。"           # 阿拉伯数字写法
```

Swift 测试端会对每个变体计算 CER，取**最小值**作为该条目的最终得分。

---

## 合成语料 (synthetic_manifest.json)

### 数据源：`scripts/synthetic_corpus.yaml`

这是合成语料的**唯一源头**。直接编辑此文件来增删改语料，不要手动编辑 `synthetic_manifest.json`。

YAML 文件包含两部分：

**1) defaults** — 按语言定义 TTS 默认参数：

```yaml
defaults:
  zh:
    say_voice: Tingting
    edge_tts_voice: zh-CN-XiaoxiaoNeural
  en:
    say_voice: Samantha
    edge_tts_voice: en-US-JennyNeural
```

**2) entries** — 语料条目列表。普通条目只需写公共字段，TTS 参数由 defaults 自动填充：

```yaml
  - id: zh_short_01
    category: chinese_short
    expected_text: "今天天气真好。"
    match_mode: character_error_rate
    match_threshold: 0.15
    language: zh
```

### 语料分类

| 分类 | 条数 | 说明 |
|------|------|------|
| 基础识别 | 6 | 中文短/长句、中英混合、英文、技术数字 |
| 静音/噪声 | 6 | 纯静音、白噪声、呼吸声（幻觉压力测试） |
| 开发者术语 | 8 | Git、Swift、Rust、K8s、REST API、SQL、URL、debug |
| 代码切换 | 13 | 句内中英混合（变量赋值、构建命令等 + Edge-TTS 中英混合） |
| 标点/语速/长音频 | 7 | 标点格式、快/慢语速、30s/60s 长音频 |
| 中途停顿 | 2 | 2s/5s 停顿后继续说话 |
| term_dictionary | ~106 | 缩写折叠、AI 产品、Apple 生态、开发工具等 |
| 回归复现 | 1 | Qwen streaming 重复 bug 复现 |

### 特殊条目类型

**合成音频**（不经过 TTS）：
```yaml
  - id: silence_01
    category: silence
    expected_text: ""
    match_mode: empty_or_whitespace
    language: none
    synthetic: true
    duration_sec: 3.0
    noise_type: white          # 可选：white / breath / 省略则为纯静音
    noise_amplitude: 0.005     # 仅 white 噪声使用
```

**复合音频**（多段拼接 + 停顿）：
```yaml
  - id: pause_mid_01
    category: mid_sentence_pause
    expected_text: "打开终端。"
    match_mode: contains_all
    match_keywords: [打开, 终端]
    language: zh
    composite: true
    segments:
      - text: "打开"
        pause_after_sec: 2.0
      - text: "终端"
        pause_after_sec: 0
```

**非默认 TTS 参数**（语速变化等）：
```yaml
  - id: rate_fast_01
    category: speech_rate
    expected_text:
      - "快速语音识别测试，1、2、3、4、5。"
      - "快速语音识别测试，一二三四五。"
    match_mode: character_error_rate
    match_threshold: 0.2
    language: zh
    say_rate: 280              # macOS say 语速
    edge_tts_rate: "+60%"      # Edge-TTS 语速
```

### 生成命令

```bash
# 完整生成（需联网，生成 Edge-TTS 合成音频）
uv run --with edge-tts --with pyyaml python scripts/generate_synthetic_corpus.py

# 仅生成合成音频（不联网，跳过 TTS，用于快速验证 YAML 格式）
uv run --with pyyaml python scripts/generate_synthetic_corpus.py --only-synthetic

# macOS say 离线备选（质量较低）
uv run --with pyyaml python scripts/generate_synthetic_corpus.py --say
```

---

## 录制语料 (recorded_manifest.json)

### 数据源

| 来源 | 条数 | 说明 | 是否需要授权 |
|------|------|------|------|
| AISHELL-1 | 8 | 标准普通话朗读 | 否 |
| MINDS-14 | 5 | 真实客服对话 | 否 |
| ASCEND | 10 | 真实中英代码切换 | 否 |
| WenetSpeech | 10 | 多场景中文（新闻/演讲/综艺） | 是（HuggingFace gated） |

### 下载命令

```bash
# 完整下载（需 HuggingFace datasets + 网络）
uv run --with 'datasets[audio]' --with soundfile --with scipy \
    python scripts/download_recorded_corpus.py

# 跳过需要授权的 WenetSpeech
uv run --with 'datasets[audio]' --with soundfile --with scipy \
    python scripts/download_recorded_corpus.py --skip-wenetspeech
```

### 维护方式

`recorded_manifest.json` 由 `download_recorded_corpus.py` 生成。如需修改录制语料的 `expected_text`（如添加多备选），可以**直接编辑** `recorded_manifest.json`，因为下载脚本不会频繁重新运行。

---

## Swift 测试端使用

### 测试类分布

| 测试类 | 语料源 | 条目数 | 用途 |
|--------|--------|--------|------|
| `QwenASRE2ETests` | synthetic_manifest.json | ~160 | E2E 识别质量 |
| `ASRPipelineBenchmarkTests` | 两者合并 | ~190 | CER 基准评估 |

### 音频加载优先级

- **合成语料**：`synthetic`
- **录制语料**：`recorded`

### 关键数据结构

Swift 端通过 `CorpusEntry.swift` 解码，`expected_text` 支持 string 和 [string] 两种 JSON 格式，统一存储为 `expectedTexts: [String]`。

---

## 日常维护操作

### 添加一条合成语料

1. 编辑 `scripts/synthetic_corpus.yaml`，在合适的分类下新增条目
2. 运行 `uv run --with pyyaml python scripts/generate_synthetic_corpus.py --only-synthetic` 验证格式
3. 运行完整生成命令生成音频
4. 在对应的 Swift 测试类中添加新的 test 方法

### 修改 expected_text（添加多备选）

1. 编辑 `scripts/synthetic_corpus.yaml`，将 `expected_text` 从 string 改为 list
2. 运行 `--only-synthetic` 重新生成 synthetic_manifest.json
3. 无需修改 Swift 端代码（已支持多备选）

### 修改录制语料的 expected_text

直接编辑 `Tests/fixtures/recorded_manifest.json`，将 `expected_text` 改为数组格式即可。

### 运行 Benchmark 查看 CER

```bash
# 全量 benchmark
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
    -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testQwenASROfflinePipeline

# 指定条目
echo "mixed_02,td_biz_04" > /tmp/benchmark_entry_filter.txt
xcodebuild test -scheme Typeless -destination 'platform=macOS' \
    -only-testing:TypelessTests/ASRPipelineBenchmarkTests/testQwenASROfflinePipeline
```

Benchmark 日志输出到 `$TMPDIR/benchmark_swift_*.log`。

---

## CI 集成

CI 工作流（`.github/workflows/ci.yml`）通过缓存机制避免重复生成音频：

```yaml
key: test-audio-v4-${{ hashFiles('scripts/generate_synthetic_corpus.py', 'scripts/synthetic_corpus.yaml') }}
```

- cache key 同时 hash 脚本和 YAML，任一变更时自动重新生成
- 录制语料需要单独下载，不在 CI 缓存范围内
