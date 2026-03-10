# Nano Typeless 项目开发备忘

## GitHub 账号

本机有两个 GitHub 账号：
- `chaoqunzhao_microsoft` - 公司账号
- `ZhaoChaoqun` - 个人账号

**typeless 是个人项目**，使用 `gh` 命令时如果遇到权限错误，请先切换到个人账号：

```bash
gh auth switch -u ZhaoChaoqun
```

## Release 构建流程

构建 Release 版本后，需要重新签名才能在本地运行：

```bash
# 1. 构建 Release
xcodebuild -scheme Typeless -configuration Release -derivedDataPath build

# 2. 重新签名 dylib 文件
cd "build/Build/Products/Release/Nano Typeless.app/Contents/Frameworks"
codesign --force --sign - libsherpa-onnx-c-api.dylib libonnxruntime.1.17.1.dylib

# 3. 重新签名整个 app
codesign --force --sign - "build/Build/Products/Release/Nano Typeless.app"
```

原因：sherpa-onnx 的 dylib 文件 Team ID 与主程序不匹配，需要使用 ad-hoc 签名（`--sign -`）重新签名。

## Python 环境管理

统一使用 `uv` 管理 Python 环境和包：

```bash
# 安装包
uv pip install <package>

# 运行 Python 脚本
uv run python script.py
```

## ModelScope 模型管理

### 仓库地址

- 仓库 ID: `zhaochaoqun/sherpa-onnx-asr-models`
- 网页: https://modelscope.cn/models/zhaochaoqun/sherpa-onnx-asr-models

### 上传模型文件

使用 ModelScope SDK 直接上传，**不需要克隆整个仓库**：

```python
import os
from modelscope.hub.api import HubApi

api = HubApi()
api.login(os.environ['MODELSCOPE_TOKEN'])  # Token 存储在环境变量中
api.upload_file(
    path_or_fileobj='本地文件路径',
    path_in_repo='仓库中的文件名',
    repo_id='zhaochaoqun/sherpa-onnx-asr-models'
)
```

### 模型文件本地缓存

缓存路径: `~/.cache/typeless-models/`

上传模型前，先检查本地缓存是否存在：
1. 如果存在，直接使用本地文件
2. 如果不存在，从 GitHub 下载到缓存目录，再上传

目录结构：
```
~/.cache/typeless-models/
├── sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2
├── sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8.tar.bz2
└── silero_vad.onnx
```

### 当前模型清单

| 模型 | 用途 | GitHub 源 |
|-----|------|----------|
| sherpa-onnx-streaming-paraformer-bilingual-zh-en | Streaming Paraformer ASR | k2-fsa/sherpa-onnx |
| sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8 | CT-Transformer 标点模型 (INT8) | k2-fsa/sherpa-onnx |
| silero_vad.onnx | VAD 语音活动检测 | k2-fsa/sherpa-onnx |

## Documentation Guidelines

所有 markdown 文档（报告、分析、设计、调研等）**必须**存放在 `/docs/` 的对应子目录中，**禁止**放置在项目根目录。仅 `README.md` 和 `CLAUDE.md` 保留在根目录。

### 目录分类规则

| 目录 | 存放内容 | 示例 |
|------|---------|------|
| `docs/architecture/` | 系统设计、集成方案、架构决策记录 (ADR) | ASR 流水线架构、Sherpa-ONNX 集成设计 |
| `docs/research/` | 模型调研、技术评估、方案对比分析 | ASR 模型选型报告、量化方案调研 |
| `docs/guides/` | 算法教程、参数配置指南、技术原理讲解 | BPE 算法指南、流式参数详解 |
| `docs/issues_and_bugs/` | Bug 根因分析、Post-Mortem、问题修复记录 | UTF-8 乱码分析、热词功能回滚复盘 |
| `docs/testing/` | 测试覆盖文档、测试计划、质量保障 | 测试用例清单、E2E 测试报告 |

### 命名规范

- 使用 `kebab-case` 小写连字符命名（如 `qwen3-asr-optimization-report.md`）
- 不使用 `SCREAMING_CASE` 大写下划线命名

### 新文档流程

1. 根据内容类型选择对应子目录
2. 如果现有目录不合适，创建新的子目录
3. 更新 `docs/README.md` 索引，添加新文档的链接和说明

## QwenASR Rust 代码管理

QwenASR 的 Rust 源码统一在 `~/Github/QwenASR`（fork 仓库）的 main 分支上维护。**不要**直接修改 `scripts/.qwen-asr-build/QwenASR/` 下的代码（该目录是构建脚本的临时目录，每次构建会被 `git reset --hard origin/main` 还原）。

### 仓库信息

- 本地路径: `~/Github/QwenASR`
- 远程 origin: `https://github.com/ZhaoChaoqun/QwenASR.git`（个人 fork）
- 远程 upstream: `https://github.com/huanglizhuo/QwenASR.git`（上游原始仓库）
- 开发分支: main（所有修改直接提交到 main）

### Rust 代码修改流程

1. 在 `~/Github/QwenASR` 的 main 分支上修改 Rust 代码并提交、push
2. 运行 `bash scripts/build-qwen-asr.sh` 构建 dylib
3. 构建脚本会自动：从 fork 拉取最新 main → 编译 → 复制 dylib 到 Frameworks

不使用 patch 文件，所有改动都在上游 repo 完成。

## Cloud Rewrite API

Cerebras GPT-OSS-120B 用于 ASR 后处理（Cloud Rewrite）。

- API Endpoint: `https://api.cerebras.ai/v1`
- 模型名: `gpt-oss-120b`
- API Key 存储在项目根目录 `.env` 文件中，变量名 `CLOUD_REWRITE_API_KEY`

使用 benchmark 脚本时：

```bash
# 从 .env 加载后运行
export $(cat .env | xargs) && uv run --with sherpa-onnx --with onnxruntime --with httpx \
    python3 scripts/benchmark_cloud_rewrite.py \
    --model gpt-oss-120b \
    --base-url https://api.cerebras.ai/v1 \
    --api-key-env CLOUD_REWRITE_API_KEY
```
