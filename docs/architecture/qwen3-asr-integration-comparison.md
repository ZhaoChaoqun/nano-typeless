# Nano Typeless 接入 Qwen3-ASR 方案对比报告

## 背景

Nano Typeless 当前已通过 **Rust FFI 方案**（`libqwen_asr.dylib`）成功集成了 Qwen3-ASR 0.6B。该方案通过 Rust 编写推理引擎 → 编译为 C ABI 的 dylib → Swift 通过 C FFI 调用。现需评估是否值得切换到 **嵌入 Python 运行时调用 mlx-audio** 的方案。

## 现有架构概览

```
Swift App (RecordingManager)
    ↓ ASREngine protocol
QwenASREngine
    ↓ C FFI (OpaquePointer)
libqwen_asr.dylib (Rust 编译)
    ↓
Qwen3-ASR 0.6B 模型 (safetensors)
```

关键接口：`qwen_asr_stream_push()` / `qwen_asr_stream_get_result()` — 完整的流式增量 API，已在 `QwenASRRecognizer.swift` 中包装完毕。

---

## 方案一：Rust FFI（当前方案）

### 技术路径

Rust 源码 → `cargo build --release` → `libqwen_asr.dylib` → Swift C FFI 调用

### 优点

| 维度 | 说明 |
|------|------|
| **已验证可用** | 当前已完整集成，流式 API 功能齐全 |
| **零运行时依赖** | 单个 dylib 文件，无需 Python/虚拟环境/包管理器 |
| **性能优秀** | Rust 编译为原生机器码，无解释器开销，无 GIL 限制 |
| **内存安全** | Rust 的 ownership 机制避免内存泄漏和 use-after-free |
| **体积小** | dylib + 模型文件，无需捆绑 Python 运行时（~100MB+） |
| **线程友好** | 无 GIL，可自由在多线程中调用，与 Swift 的 GCD 完美配合 |
| **架构一致** | 与现有 sherpa-onnx 的集成方式（C FFI dylib）完全一致 |
| **代码签名简单** | 只需对 dylib 做 ad-hoc 签名，与现有流程一致 |
| **Apple 芯片优化** | 可通过 Accelerate framework 和 Metal 后端优化矩阵运算 |

### 缺点

| 维度 | 说明 |
|------|------|
| **开发门槛高** | 需要 Rust ML 生态知识（candle/burn 等框架） |
| **模型适配工作** | 需自行实现 Qwen3-ASR 的 Transformer 推理逻辑 |
| **上游更新慢** | Qwen 官方先发布 PyTorch 权重，Rust 端需手动移植 |
| **调试困难** | C FFI 边界的 crash 调试比纯 Swift 复杂 |
| **Metal 后端成熟度** | Candle 的 Metal 后端不如 MLX 成熟，部分算子可能缺失 |

### 当前实现状态

- `qwen_asr.h`：完整的 C API，包含加载/释放/流式推送/配置等 17 个函数
- `QwenASRRecognizer.swift`：82 行的轻量包装
- `ASREngine.swift` 中的 `QwenASREngine`：已接入 `RecordingManager` 工作流
- 流式参数可调：chunk_sec / rollback / unfixed_chunks / max_new_tokens

---

## 方案二：嵌入 Python 运行时调用 mlx-audio

### 技术路径

Swift App → 某种 Python 调用方式 → mlx-audio (Python) → MLX 框架 → Qwen3-ASR

### mlx-audio 简介

mlx-audio 是基于 Apple MLX 框架的音频处理库，支持 TTS / STT / STS 等功能。已支持 Qwen3-ASR：

```python
from mlx_audio.stt import load

model = load("mlx-community/Qwen3-ASR-0.6B-8bit")
result = model.generate("audio.wav", language="Chinese")
print(result.text)
```

### 三种子方案对比

#### 2a. subprocess 调用 Python 脚本

```
Swift → Process() → python3 → mlx-audio → stdout JSON
```

| 维度 | 评估 |
|------|------|
| 实现难度 | 低 |
| 延迟 | **极高**（进程启动 2-5s + Python 导入 3-8s + 模型加载） |
| 流式支持 | 困难（需自建 IPC 协议，stdout 逐行解析） |
| App 体积 | **+500MB~1GB**（需捆绑 Python 3.x + mlx + mlx-audio + 依赖） |
| 稳定性 | 低（子进程崩溃需额外处理） |
| 沙盒兼容 | 差（macOS 沙盒限制 subprocess 执行） |

#### 2b. XPC Service

```
Swift App ←XPC→ Python Helper → mlx-audio
```

| 维度 | 评估 |
|------|------|
| 实现难度 | 高（需配置 XPC Service target + launchd + entitlements） |
| 延迟 | 中（首次启动慢，后续保活可接受） |
| 流式支持 | 可行（XPC 支持双向消息） |
| 进程隔离 | 好（Python 崩溃不影响主进程） |
| 架构复杂度 | **极高**（双 target、两套构建流水线、XPC 协议定义） |
| App 体积 | **+500MB~1GB**（同样需捆绑 Python） |

#### 2c. PythonKit 内嵌

```
Swift → PythonKit → libpython.dylib → mlx-audio → MLX
```

| 维度 | 评估 |
|------|------|
| 实现难度 | 中 |
| 延迟 | 中低（内存直调，但首次 import 较慢） |
| 流式支持 | 可行（直接调 Python 对象方法） |
| GIL 限制 | **严重**——Python GIL 会阻塞 Swift 调用线程 |
| 打包复杂度 | **极高**（需捆绑 `libpython3.x.dylib` + site-packages + .so 扩展） |
| App 体积 | **+300MB~800MB** |
| 类型安全 | 无（PythonKit 全部是动态类型，运行时出错） |
| 签名/公证 | **极其困难**（每个 .so/.dylib 都需签名，mlx 本身含 Metal shader） |

---

## 核心维度对比

| 维度 | Rust FFI | 嵌入 Python (最佳子方案) |
|------|----------|------------------------|
| **当前可用性** | ✅ 已完成 | ❌ 需全新开发 |
| **运行时延迟** | ~10ms per chunk | ~50-200ms（GIL + Python 开销） |
| **首次启动** | 模型加载 2-5s | Python 启动 + import + 模型加载 8-15s |
| **App 体积增量** | ~5MB (dylib) | +300MB~1GB (Python 运行时+依赖) |
| **流式识别** | 原生支持（C API） | 需适配（mlx-audio 主要面向批量） |
| **线程模型** | 无限制 | Python GIL 单线程瓶颈 |
| **内存效率** | Rust 精确控制 | Python 对象开销 + MLX tensor |
| **代码签名/公证** | 简单（1 个 dylib） | 极复杂（数百个 .so/.dylib） |
| **Mac App Store** | 可行 | 几乎不可能（Python 捆绑不符合审核要求） |
| **沙盒兼容** | 完全兼容 | subprocess 方案不兼容 |
| **架构一致性** | 与 sherpa-onnx 一致 | 引入全新技术栈 |
| **上游模型更新** | 需手动适配 | mlx-audio 社区跟进快 |
| **MLX 硬件优化** | 无（需自建 Metal 后端） | ✅ MLX 原生 Apple Silicon 优化 |
| **开发维护成本** | 中（Rust 推理代码） | 高（Python 打包+调试+签名） |

---

## mlx-audio 的真正价值

mlx-audio 基于 Apple 的 MLX 框架，能充分利用 Apple Silicon 统一内存架构，推理效率高。但它的设计目标是 **Python 生态的本地开发和实验**，而非嵌入到原生 App 中分发。

如果要获得 MLX 的硬件优化优势，更合理的路径是：

| 路径 | 可行性 | 说明 |
|------|--------|------|
| 等待 mlx-swift 支持 audio | 低 | mlx-swift 目前仅支持 LLM/VLM，无 audio 模块 |
| 用 mlx-swift 自建 Qwen3 推理 | 中高 | mlx-swift 提供底层 tensor 和 nn 模块，但需自行实现 Qwen3 架构 |
| Rust + Metal Backend | 中 | 通过 candle-metal 或 burn-metal 利用 GPU |

---

## 结论与建议

**推荐维持方案一（Rust FFI）**，理由如下：

1. **已经可用**——当前的 `libqwen_asr.dylib` 已完整实现流式 API 并接入主流程，切换方案需要重新开发
2. **分发友好**——单 dylib 文件，签名简单，不增加显著体积，兼容沙盒和 App Store
3. **性能确定性**——无 GIL、无解释器开销、无 Python 启动延迟
4. **架构一致**——与现有 sherpa-onnx 的 C FFI 集成方式完全对齐，维护成本可预期

嵌入 Python 方案的唯一优势是跟进 mlx-audio 上游更新更轻松，但带来的打包复杂度、体积膨胀、GIL 限制和签名公证问题远超收益。

**如果未来需要 MLX 硬件优化**，建议关注 mlx-swift 的 audio 支持进展，或考虑在 Rust FFI 层集成 Metal compute shader 加速关键算子，而非嵌入整个 Python 运行时。
