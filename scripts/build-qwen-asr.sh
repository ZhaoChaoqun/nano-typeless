#!/bin/bash
#
# 构建 QwenASR macOS dylib（含 Streaming FFI）
#
# 流程：
#   1. 克隆/更新 QwenASR 仓库
#   2. 应用 patch（crate-type, cfg 解除, streaming C FFI）
#   3. cargo build --release
#   4. 复制 dylib，修复 install_name，签名
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/.qwen-asr-build"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks/qwen-asr"
REPO_URL="https://github.com/huanglizhuo/QwenASR.git"
PATCH_FILE="$SCRIPT_DIR/qwen-asr-macos-streaming.patch"

echo "=== QwenASR dylib 构建脚本 ==="
echo "项目目录: $PROJECT_DIR"
echo "构建目录: $BUILD_DIR"
echo ""

# 检查 Rust 工具链
if ! command -v cargo &> /dev/null; then
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    if ! command -v cargo &> /dev/null; then
        echo "错误: 未找到 cargo，请先安装 Rust: https://rustup.rs/"
        exit 1
    fi
fi

# 检查 patch 文件
if [ ! -f "$PATCH_FILE" ]; then
    echo "错误: 未找到 patch 文件: $PATCH_FILE"
    exit 1
fi

# 克隆或更新仓库
if [ -d "$BUILD_DIR/QwenASR" ]; then
    echo ">>> 重置并更新已有的 QwenASR 仓库..."
    cd "$BUILD_DIR/QwenASR"
    git checkout -- .
    git pull --ff-only || true
else
    echo ">>> 克隆 QwenASR 仓库..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    git clone "$REPO_URL"
fi

cd "$BUILD_DIR/QwenASR"

# 应用 patch（包含 Cargo.toml crate-type、lib.rs cfg 解除、c_api.rs streaming FFI）
echo ">>> 应用 macOS streaming patch..."
git apply "$PATCH_FILE"
echo "    patch 应用成功"

# 构建
echo ""
echo ">>> 开始编译 (Release mode)..."
echo "    RUSTFLAGS=\"-C target-cpu=native\""
echo ""

RUSTFLAGS="-C target-cpu=native" cargo build --release --features ios 2>&1

echo ""
echo ">>> 编译完成"

# 复制产物
DYLIB_SRC="target/release/libqwen_asr.dylib"
STATICLIB_SRC="target/release/libqwen_asr.a"

if [ ! -f "$DYLIB_SRC" ]; then
    echo "错误: 未找到 $DYLIB_SRC"
    echo "尝试查找可用的库文件..."
    find target/release -name "libqwen_asr*" -type f 2>/dev/null
    exit 1
fi

mkdir -p "$FRAMEWORK_DIR/lib"
mkdir -p "$FRAMEWORK_DIR/include"

echo ">>> 复制 dylib..."
cp "$DYLIB_SRC" "$FRAMEWORK_DIR/lib/"

if [ -f "$STATICLIB_SRC" ]; then
    echo ">>> 复制 staticlib..."
    cp "$STATICLIB_SRC" "$FRAMEWORK_DIR/lib/"
fi

# 修复 install_name
echo ">>> 修复 install_name..."
install_name_tool -id @rpath/libqwen_asr.dylib "$FRAMEWORK_DIR/lib/libqwen_asr.dylib"

# Ad-hoc 签名
echo ">>> Ad-hoc 签名..."
codesign --force --sign - "$FRAMEWORK_DIR/lib/libqwen_asr.dylib"

# 验证
echo ""
echo "=== 构建结果 ==="
ls -lh "$FRAMEWORK_DIR/lib/"
echo ""
echo ">>> dylib 依赖:"
otool -L "$FRAMEWORK_DIR/lib/libqwen_asr.dylib"
echo ""
echo ">>> 导出符号 (qwen_asr):"
nm -gU "$FRAMEWORK_DIR/lib/libqwen_asr.dylib" | grep qwen_asr || echo "  (未找到符号)"
echo ""

# 统计 streaming 符号
STREAM_COUNT=$(nm -gU "$FRAMEWORK_DIR/lib/libqwen_asr.dylib" | grep -c "qwen_asr_stream" || true)
echo ">>> Streaming API 符号数: $STREAM_COUNT"
if [ "$STREAM_COUNT" -lt 9 ]; then
    echo "警告: 预期 9 个 streaming 符号，实际 $STREAM_COUNT 个"
fi

echo ""
echo "=== 完成 ==="
