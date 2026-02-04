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
