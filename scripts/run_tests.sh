#!/usr/bin/env bash
# scripts/run_tests.sh -- 运行 ASR 测试并生成对比报告
#
# 用法:
#   bash scripts/run_tests.sh e2e            # 运行 E2E 测试
#   bash scripts/run_tests.sh benchmark      # 运行 Benchmark 测试
#   bash scripts/run_tests.sh e2e --open     # 运行后打开报告

set -euo pipefail

SUITE="${1:-e2e}"
OPEN_REPORT=false
for arg in "$@"; do
    if [ "$arg" = "--open" ]; then
        OPEN_REPORT=true
    fi
done

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS_DIR="$PROJECT_ROOT/tests/reports"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
GIT_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

mkdir -p "$REPORTS_DIR"

# 确定测试目标
if [ "$SUITE" = "e2e" ]; then
    TEST_TARGET="TypelessTests/QwenASRE2ETests"
elif [ "$SUITE" = "benchmark" ]; then
    TEST_TARGET="TypelessTests/ASRPipelineBenchmarkTests"
else
    echo "[run_tests] 未知的测试套件: $SUITE (可选: e2e, benchmark)"
    exit 1
fi

# 通过临时文件将配置传递给 Swift 测试进程
# （xcodebuild 不会将 shell 环境变量传递给测试进程）
JSON_OUTPUT="${TMPDIR:-/tmp}/typeless_${SUITE}_results.json"
CONFIG_FILE="/tmp/typeless_test_config.txt"
cat > "$CONFIG_FILE" <<EOF
json_path=$JSON_OUTPUT
git_commit=$GIT_COMMIT
git_branch=$GIT_BRANCH
EOF

# 清理上次的输出
rm -f "$JSON_OUTPUT"

# 运行 xcodebuild
echo "[run_tests] 运行 $SUITE 测试 (commit: $GIT_COMMIT, branch: $GIT_BRANCH)..."
echo "[run_tests] 测试目标: $TEST_TARGET"

# xcodebuild test 即使有 case 失败也返回非零，用 || true 避免脚本中断
xcodebuild test \
    -scheme Typeless \
    -destination 'platform=macOS' \
    -only-testing:"$TEST_TARGET" \
    2>&1 | tail -30 || true

# 检查 JSON 输出
if [ ! -f "$JSON_OUTPUT" ]; then
    echo "[run_tests] 错误: 未找到 JSON 输出 ($JSON_OUTPUT)"
    echo "[run_tests] 测试可能未正常运行或 TestResultCollector 未被调用"
    exit 1
fi

# 复制 JSON 到 reports 目录
RESULT_FILE="$REPORTS_DIR/${SUITE}_${TIMESTAMP}.json"
cp "$JSON_OUTPUT" "$RESULT_FILE"
echo "[run_tests] 结果已保存: $RESULT_FILE"

# 更新 latest 符号链接
ln -sf "$(basename "$RESULT_FILE")" "$REPORTS_DIR/latest_${SUITE}.json"

# 查找上次的 JSON 文件用于对比
# shellcheck disable=SC2012
PREV_FILE=$(ls -1t "$REPORTS_DIR"/${SUITE}_*.json 2>/dev/null \
    | grep -v "$(basename "$RESULT_FILE")" \
    | head -1 || true)

PREV_ARG=()
if [ -n "$PREV_FILE" ]; then
    PREV_ARG=(--previous "$PREV_FILE")
    echo "[run_tests] 对比基准: $(basename "$PREV_FILE")"
fi

# 生成报告
REPORT_PATH="$PROJECT_ROOT/docs/testing/${SUITE}-report-latest.md"

uv run python "$PROJECT_ROOT/scripts/generate_test_report.py" \
    --current "$RESULT_FILE" \
    "${PREV_ARG[@]}" \
    --output "$REPORT_PATH"

echo "[run_tests] 报告已生成: $REPORT_PATH"

# 清理旧文件（保留最近 10 个）
# shellcheck disable=SC2012
ls -1t "$REPORTS_DIR"/${SUITE}_*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true

# 可选打开报告
if [ "$OPEN_REPORT" = true ]; then
    open "$REPORT_PATH"
fi
