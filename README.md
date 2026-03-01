<p align="center">
  <img src="https://img.icons8.com/fluency/96/microphone.png" width="80" />
</p>

<h1 align="center">Nano Typeless</h1>

<p align="center">
  <strong>按下即说，语音秒变文字</strong><br>
  基于本地 AI 的 macOS 原生语音输入工具
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue?logo=apple&logoColor=white" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
  <a href="#"><img src="https://img.shields.io/badge/ASR-3%20Engines-purple" alt="ASR Engines"></a>
</p>

<p align="center">
  <a href="#-功能特性">功能特性</a> •
  <a href="#-安装方法">安装方法</a> •
  <a href="#-使用方法">使用方法</a> •
  <a href="#-项目架构">项目架构</a> •
  <a href="#-参与贡献">参与贡献</a>
</p>

<p align="center">
  <a href="#english">English</a>
</p>

---

## 🎬 演示视频

https://github.com/user-attachments/assets/c99ec06a-e728-448b-9563-4a2872ebfef5

## ✨ 功能特性

| 功能 | 描述 |
|------|------|
| 🎤 **按键说话** | 按住 `Fn` 键录音，松开即转文字 |
| 🔒 **完全本地** | 所有模型完全在本地运行，数据不出设备 |
| 🌐 **中英混合** | 三种引擎均原生支持中英文混合输入 |
| ⚡ **快速轻量** | 菜单栏应用，资源占用极低 |
| 🎯 **通用输入** | 任意应用可用 - 光标在哪，文字就输入到哪 |
| 💻 **通用版本** | **同时支持 Apple Silicon (M1/M2/M3/M4) 和 Intel Mac** |

## 🖥️ 系统要求

| 要求 | 规格 |
|------|------|
| **系统** | macOS 14.0 (Sonoma) 或更高版本 |
| **芯片** | **Apple Silicon (M1/M2/M3/M4) 或 Intel - 通用版本支持** |
| **内存** | 建议 8GB 以上 |

> **说明**：Apple Silicon Mac 将利用神经网络引擎加速推理。Intel Mac 使用 CPU 推理，功能完整。

## 📦 安装方法

### 通过 Homebrew 安装（推荐）

```bash
# 安装
brew tap ZhaoChaoqun/typeless && brew install --cask nano-typeless && xattr -cr "/Applications/Nano Typeless.app"
```

### 升级

```bash
# 升级到最新版本
brew update && brew upgrade nano-typeless && xattr -cr "/Applications/Nano Typeless.app"
```

### 从源码编译

```bash
# 克隆仓库
git clone https://github.com/ZhaoChaoqun/nano-typeless.git
cd nano-typeless

# 用 Xcode 打开
open Typeless.xcodeproj

# 或命令行编译
xcodebuild -project Typeless.xcodeproj -scheme Typeless build
```

### 首次启动设置

首次启动需要授予两个权限：

| 权限 | 用途 | 如何开启 |
|------|------|----------|
| 🎙️ **麦克风** | 录制语音 | 系统弹窗（自动） |
| ♿ **辅助功能** | 监听全局 `Fn` 键 | 系统设置 → 隐私与安全性 → 辅助功能 |

> **提示**：授予辅助功能权限后，可能需要重启应用。

## 🚀 使用方法

<table>
<tr>
<td width="60%">

### 快速开始

1. **启动** Nano Typeless - 出现在菜单栏
2. **按住** `Fn` 键开始说话
3. **松开** `Fn` 键完成录音
4. **文字** 自动插入到光标位置

### 使用流程

```
[按住 Fn] → "你好，这是一个测试" → [松开 Fn]
                    ↓
         "你好，这是一个测试" 出现在光标处
```

</td>
<td width="40%">

### 状态指示

| 状态 | 指示器 |
|------|--------|
| 就绪 | 🎵 菜单栏图标 |
| 录音中 | 🔴 视觉遮罩 |
| 处理中 | ⏳ 加载指示器 |

</td>
</tr>
</table>

## 🏗️ 项目架构

```
typeless/
├── Sources/
│   ├── TypelessApp.swift          # 应用入口和生命周期
│   ├── RecordingManager.swift     # 音频录制和引擎调度
│   ├── ASREngine.swift            # ASR 引擎统一协议
│   ├── SherpaOnnxRecognizer.swift # SenseVoice Nano 离线识别
│   ├── SherpaOnnxOnlineRecognizer.swift # Streaming Paraformer 流式识别
│   ├── QwenASRRecognizer.swift    # Qwen3-ASR 流式识别
│   ├── KeyMonitor.swift           # 全局 Fn 键检测
│   ├── TextInserter.swift         # 光标文字插入
│   ├── OverlayWindow.swift        # 录音 UI 遮罩
│   └── SettingsView.swift         # 偏好设置 UI
├── Frameworks/
│   ├── sherpa-onnx/               # FunASR + Paraformer 推理框架
│   └── qwen-asr/                  # Qwen3-ASR Rust FFI 库
├── Package.swift                  # Swift Package 依赖
└── Typeless.xcodeproj/            # Xcode 项目
```

### 技术栈

| 组件 | 技术 |
|------|------|
| **UI 框架** | SwiftUI |
| **语音识别** | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (SenseVoice Nano + Paraformer) / Qwen3-ASR (Rust FFI) |
| **音频采集** | AVFoundation |
| **按键监听** | CGEvent Tap API |
| **文字插入** | CGEvent（键盘模拟） |

### 工作原理

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Fn 键      │────▶│   录制       │────▶│   ASR 引擎  │────▶│   插入       │
│  监听       │     │   音频       │     │   转写      │     │   文字       │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
    CGEvent           AVFoundation         本地 AI           CGEvent
```

## 🔧 配置说明

应用内置三种 ASR 引擎，可在设置中切换。默认使用 `Streaming Paraformer`。

| 引擎 | 大小 | 模式 | 标点 | 适用场景 |
|------|------|------|------|----------|
| `Streaming Paraformer` | ~216MB + 标点 62MB | 流式 | 需 CT-Transformer | 日常使用（默认） |
| `SenseVoice Nano` | ~179MB | 离线（VAD 分段） | 需 CT-Transformer | 方言、口音识别 |
| `Qwen3-ASR` | ~1.2GB | 流式 | 自带标点 | 高精度，长文本 |

## 🤝 参与贡献

欢迎贡献！请随时提交 Pull Request。

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 📄 许可证

本项目基于 MIT 许可证开源 - 详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [FunASR](https://github.com/modelscope/FunASR) - 阿里达摩院开源语音识别模型
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - 跨平台语音识别推理框架
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3) - 通义千问大模型语音识别

---

<h1 id="english" align="center">English</h1>

<p align="center">
  <strong>Press. Speak. Type.</strong><br>
  A native macOS voice-to-text tool powered by local AI
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-usage">Usage</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-contributing">Contributing</a>
</p>

---

## 🎬 Demo

https://github.com/user-attachments/assets/c99ec06a-e728-448b-9563-4a2872ebfef5

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎤 **Push-to-Talk** | Hold `Fn` key to record, release to transcribe |
| 🔒 **100% Local** | All models run entirely on-device, no data leaves your Mac |
| 🌐 **Multilingual** | Three ASR engines with native Chinese-English mixed input support |
| ⚡ **Fast & Lightweight** | Menu bar app with minimal resource usage |
| 🎯 **Universal Input** | Works in any app - just position your cursor and speak |
| 💻 **Universal Binary** | **Runs natively on both Apple Silicon (M1/M2/M3/M4) and Intel Macs - one app, all Macs** |

## 🖥️ System Requirements

| Requirement | Specification |
|-------------|---------------|
| **OS** | macOS 14.0 (Sonoma) or later |
| **Chip** | **Apple Silicon (M1/M2/M3/M4) or Intel - Universal Binary supported** |
| **RAM** | 8GB+ recommended |

> **Note**: Apple Silicon Macs will utilize the Neural Engine for faster inference. Intel Macs use CPU-based inference with full functionality.

## 📦 Installation

### Install via Homebrew (Recommended)

```bash
# Install
brew tap ZhaoChaoqun/typeless && brew install --cask nano-typeless && xattr -cr "/Applications/Nano Typeless.app"
```

### Upgrade

```bash
# Upgrade to latest version
brew update && brew upgrade nano-typeless && xattr -cr "/Applications/Nano Typeless.app"
```

### Build from Source

```bash
# Clone the repository
git clone https://github.com/ZhaoChaoqun/nano-typeless.git
cd nano-typeless

# Open in Xcode
open Typeless.xcodeproj

# Or build via command line
xcodebuild -project Typeless.xcodeproj -scheme Typeless build
```

### First Launch Setup

On first launch, you'll need to grant two permissions:

| Permission | Purpose | How to Enable |
|------------|---------|---------------|
| 🎙️ **Microphone** | Record your voice | System Prompt (automatic) |
| ♿ **Accessibility** | Listen for global `Fn` key | System Settings → Privacy & Security → Accessibility |

> **Tips**: After granting Accessibility permission, you may need to restart the app.

## 🚀 Usage

<table>
<tr>
<td width="60%">

### Quick Start

1. **Launch** Nano Typeless - it appears in your menu bar
2. **Hold** the `Fn` key and start speaking
3. **Release** the `Fn` key when done
4. **Text** is automatically inserted at cursor position

### Workflow Example

```
[Hold Fn] → "Hello, this is a test" → [Release Fn]
                    ↓
         "Hello, this is a test" appears at cursor
```

</td>
<td width="40%">

### Status Indicators

| State | Indicator |
|-------|-----------|
| Ready | 🎵 Menu bar icon |
| Recording | 🔴 Visual overlay |
| Processing | ⏳ Loading indicator |

</td>
</tr>
</table>

## 🏗️ Architecture

```
typeless/
├── Sources/
│   ├── TypelessApp.swift          # App entry & lifecycle
│   ├── RecordingManager.swift     # Audio recording & engine dispatch
│   ├── ASREngine.swift            # Unified ASR engine protocol
│   ├── SherpaOnnxRecognizer.swift # SenseVoice Nano offline recognition
│   ├── SherpaOnnxOnlineRecognizer.swift # Streaming Paraformer
│   ├── QwenASRRecognizer.swift    # Qwen3-ASR streaming recognition
│   ├── KeyMonitor.swift           # Global Fn key detection
│   ├── TextInserter.swift         # Cursor text insertion
│   ├── OverlayWindow.swift        # Recording UI overlay
│   └── SettingsView.swift         # Preferences UI
├── Frameworks/
│   ├── sherpa-onnx/               # FunASR + Paraformer inference
│   └── qwen-asr/                  # Qwen3-ASR Rust FFI library
├── Package.swift                  # Swift Package dependencies
└── Typeless.xcodeproj/            # Xcode project
```

### Tech Stack

| Component | Technology |
|-----------|------------|
| **UI Framework** | SwiftUI |
| **Speech Recognition** | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (SenseVoice Nano + Paraformer) / Qwen3-ASR (Rust FFI) |
| **Audio Capture** | AVFoundation |
| **Key Monitoring** | CGEvent Tap API |
| **Text Insertion** | CGEvent (Keyboard Simulation) |

### How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Fn Key     │────▶│   Record     │────▶│  ASR Engine │────▶│   Insert     │
│  Monitor    │     │   Audio      │     │  Transcribe │     │   Text       │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
    CGEvent           AVFoundation         Local AI           CGEvent
```

## 🔧 Configuration

The app includes three built-in ASR engines, switchable in Settings. Default is `Streaming Paraformer`.

| Engine | Size | Mode | Punctuation | Best For |
|--------|------|------|-------------|----------|
| `Streaming Paraformer` | ~216MB + punct 62MB | Streaming | CT-Transformer | Daily use (default) |
| `SenseVoice Nano` | ~179MB | Offline (VAD) | CT-Transformer | Dialects & accents |
| `Qwen3-ASR` | ~1.2GB | Streaming | Built-in | High accuracy, long text |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [FunASR](https://github.com/modelscope/FunASR) - Alibaba DAMO Academy's open-source speech recognition model
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - Cross-platform speech recognition inference framework
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3) - Qwen large model speech recognition

---

<p align="center">
  Made with ❤️ for the macOS community
</p>
