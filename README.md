<p align="center">
  <img src="https://img.icons8.com/fluency/96/microphone.png" width="80" />
</p>

<h1 align="center">Typeless</h1>

<p align="center">
  <strong>Press. Speak. Type.</strong><br>
  A native macOS voice-to-text tool powered by local Whisper AI
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue?logo=apple&logoColor=white" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
  <a href="#"><img src="https://img.shields.io/badge/AI-WhisperKit-purple" alt="WhisperKit"></a>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contributing">Contributing</a>
</p>

---

## 🎬 Demo

https://github.com/user-attachments/assets/c99ec06a-e728-448b-9563-4a2872ebfef5

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎤 **Push-to-Talk** | Hold `Fn` key to record, release to transcribe |
| 🔒 **100% Local** | Whisper model runs entirely on-device, no data leaves your Mac |
| 🌐 **Multilingual** | Native support for Chinese-English mixed input |
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
brew tap ZhaoChaoqun/typeless && brew install --cask nano-typeless && xattr -cr /Applications/Typeless.app
```

### Upgrade

```bash
# Upgrade to latest version
brew update && brew upgrade nano-typeless && xattr -cr /Applications/Typeless.app
```

### Build from Source

```bash
# Clone the repository
git clone https://github.com/ZhaoChaoqun/typeless.git
cd typeless

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

1. **Launch** Typeless - it appears in your menu bar
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
│   ├── TypelessApp.swift      # App entry & lifecycle
│   ├── RecordingManager.swift # Audio recording & WhisperKit
│   ├── KeyMonitor.swift       # Global Fn key detection
│   ├── TextInserter.swift     # Cursor text insertion
│   ├── OverlayWindow.swift    # Recording UI overlay
│   └── SettingsView.swift     # Preferences UI
├── Package.swift              # Swift Package dependencies
└── Typeless.xcodeproj/        # Xcode project
```

### Tech Stack

| Component | Technology |
|-----------|------------|
| **UI Framework** | SwiftUI |
| **Speech Recognition** | [WhisperKit](https://github.com/argmaxinc/WhisperKit) (OpenAI Whisper) |
| **Audio Capture** | AVFoundation |
| **Key Monitoring** | CGEvent Tap API |
| **Text Insertion** | CGEvent (Keyboard Simulation) |

### How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Fn Key     │────▶│   Record     │────▶│  WhisperKit │────▶│   Insert     │
│  Monitor    │     │   Audio      │     │  Transcribe │     │   Text       │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
    CGEvent           AVFoundation         Local AI           CGEvent
```

## 🔧 Configuration

The app uses the `base` Whisper model by default, offering a good balance between speed and accuracy for Chinese-English mixed content.

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| `tiny` | ~40MB | ⚡⚡⚡ | ⭐⭐ | Quick notes |
| `base` | ~140MB | ⚡⚡ | ⭐⭐⭐ | Daily use (default) |
| `small` | ~460MB | ⚡ | ⭐⭐⭐⭐ | Higher accuracy |

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

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - Swift implementation of OpenAI's Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) - Speech recognition model

---

<p align="center">
  Made with ❤️ for the macOS community
</p>
