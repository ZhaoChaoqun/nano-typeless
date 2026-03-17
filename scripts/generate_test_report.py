#!/usr/bin/env python3
"""
ASR 测试报告生成器

读取 JSON 测试结果文件，生成 Markdown 对比报告。
支持 E2E（单 pipeline）和 Benchmark（多 pipeline）格式。

用法:
  uv run python scripts/generate_test_report.py --current <path.json> [--previous <path.json>] [-o <report.md>]
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_json(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def get_pipelines(data: dict) -> list[dict]:
    return data.get("pipelines", [])


def entries_by_id(pipeline: dict) -> dict[str, dict]:
    return {e["id"]: e for e in pipeline.get("entries", [])}


# ---------------------------------------------------------------------------
# Comparison logic
# ---------------------------------------------------------------------------

CER_THRESHOLD = 0.005  # delta below this is considered "no change"


def compare_entries(
    current_map: dict[str, dict],
    previous_map: dict[str, dict] | None,
) -> dict:
    """Compare current entries against previous, classify into categories."""
    improved = []
    regressed = []
    new_entries = []
    removed = []

    if previous_map is None:
        return {
            "improved": [],
            "regressed": [],
            "new": list(current_map.keys()),
            "removed": [],
        }

    all_ids = set(current_map.keys()) | set(previous_map.keys())
    for eid in sorted(all_ids):
        cur = current_map.get(eid)
        prev = previous_map.get(eid)
        if cur and not prev:
            new_entries.append(eid)
        elif prev and not cur:
            removed.append(eid)
        elif cur and prev:
            delta = cur.get("cer", 0) - prev.get("cer", 0)
            if delta < -CER_THRESHOLD:
                improved.append((eid, prev["cer"], cur["cer"], delta))
            elif delta > CER_THRESHOLD:
                regressed.append((eid, prev["cer"], cur["cer"], delta))

    # Sort by absolute delta
    improved.sort(key=lambda x: x[3])
    regressed.sort(key=lambda x: -x[3])

    return {
        "improved": improved,
        "regressed": regressed,
        "new": new_entries,
        "removed": removed,
    }


# ---------------------------------------------------------------------------
# Markdown generation
# ---------------------------------------------------------------------------

def fmt_cer(v: float) -> str:
    return f"{v:.3f}"


def fmt_pct(n: int, total: int) -> str:
    if total == 0:
        return "0 (0.0%)"
    return f"{n} ({100 * n / total:.1f}%)"


def fmt_delta(v: float, invert: bool = False) -> str:
    """Format delta with direction arrow. invert=True means lower is better."""
    if abs(v) < 0.0005:
        return "-"
    sign = "+" if v > 0 else ""
    arrow = ""
    if invert:
        arrow = " ↓" if v < 0 else " ↑"
    else:
        arrow = " ↑" if v > 0 else " ↓"
    return f"{sign}{v:.3f}{arrow}"


def truncate(s: str, maxlen: int = 40) -> str:
    if len(s) <= maxlen:
        return s
    return s[:maxlen - 3] + "..."


def generate_pipeline_report(
    pipeline: dict,
    prev_pipeline: dict | None,
    heading_level: int = 2,
) -> list[str]:
    """Generate the 4-section report for a single pipeline."""
    lines: list[str] = []
    h = "#" * heading_level

    name = pipeline["pipeline_name"]
    summary = pipeline["summary"]
    cur_map = entries_by_id(pipeline)
    prev_map = entries_by_id(prev_pipeline) if prev_pipeline else None
    prev_summary = prev_pipeline.get("summary") if prev_pipeline else None
    comparison = compare_entries(cur_map, prev_map)

    lines.append(f"{h} {name}")
    lines.append("")

    # ── Section 1: Summary ──
    lines.append(f"{h}# 1. 总览")
    lines.append("")

    if prev_summary:
        lines.append("| 指标 | 当前 | 上次 | 变化 |")
        lines.append("|------|:----:|:----:|:----:|")
        lines.append(
            f"| 总条目 | {summary['total_entries']} | {prev_summary['total_entries']} | - |"
        )
        lines.append(
            f"| 通过 | {fmt_pct(summary['passed'], summary['total_entries'])} "
            f"| {fmt_pct(prev_summary['passed'], prev_summary['total_entries'])} "
            f"| {summary['passed'] - prev_summary['passed']:+d} |"
        )
        lines.append(
            f"| 失败 | {fmt_pct(summary['failed'], summary['total_entries'])} "
            f"| {fmt_pct(prev_summary['failed'], prev_summary['total_entries'])} "
            f"| {summary['failed'] - prev_summary['failed']:+d} |"
        )
        avg_delta = summary["avg_cer"] - prev_summary["avg_cer"]
        lines.append(
            f"| 平均 CER | {fmt_cer(summary['avg_cer'])} | {fmt_cer(prev_summary['avg_cer'])} "
            f"| {fmt_delta(avg_delta, invert=True)} |"
        )
        lines.append(
            f"| 中位 CER | {fmt_cer(summary['median_cer'])} | {fmt_cer(prev_summary['median_cer'])} "
            f"| {fmt_delta(summary['median_cer'] - prev_summary['median_cer'], invert=True)} |"
        )
        rtf_delta = summary["rtf"] - prev_summary["rtf"]
        lines.append(
            f"| RTF | {summary['rtf']:.3f}x | {prev_summary['rtf']:.3f}x "
            f"| {fmt_delta(rtf_delta, invert=True)} |"
        )
    else:
        lines.append("| 指标 | 值 |")
        lines.append("|------|:--:|")
        lines.append(f"| 总条目 | {summary['total_entries']} |")
        lines.append(f"| 通过 | {fmt_pct(summary['passed'], summary['total_entries'])} |")
        lines.append(f"| 失败 | {fmt_pct(summary['failed'], summary['total_entries'])} |")
        lines.append(f"| 平均 CER | {fmt_cer(summary['avg_cer'])} |")
        lines.append(f"| 中位 CER | {fmt_cer(summary['median_cer'])} |")
        lines.append(f"| 总推理时长 | {summary['total_inference_time_sec']:.1f}s |")
        lines.append(f"| RTF | {summary['rtf']:.3f}x |")

    lines.append("")

    # ── Section 2: Improved ──
    lines.append(f"{h}# 2. 改善的 Case (CER ↓)")
    lines.append("")

    if not prev_map:
        lines.append("*无历史数据可对比。*")
    elif not comparison["improved"]:
        lines.append("*无改善的条目。*")
    else:
        lines.append("| # | ID | 类别 | CER (上次 → 本次) | 变化 |")
        lines.append("|---|-----|------|:-----------------:|:----:|")
        for i, (eid, prev_cer, cur_cer, delta) in enumerate(comparison["improved"], 1):
            entry = cur_map[eid]
            lines.append(
                f"| {i} | {eid} | {entry['category']} "
                f"| {fmt_cer(prev_cer)} → {fmt_cer(cur_cer)} | **{delta:+.3f}** |"
            )
    lines.append("")

    # ── Section 3: Regressed ──
    lines.append(f"{h}# 3. 退化的 Case (CER ↑)")
    lines.append("")

    if not prev_map:
        lines.append("*无历史数据可对比。*")
    elif not comparison["regressed"]:
        lines.append("*无退化的条目。*")
    else:
        lines.append("| # | ID | 类别 | CER (上次 → 本次) | 变化 |")
        lines.append("|---|-----|------|:-----------------:|:----:|")
        for i, (eid, prev_cer, cur_cer, delta) in enumerate(comparison["regressed"], 1):
            entry = cur_map[eid]
            lines.append(
                f"| {i} | {eid} | {entry['category']} "
                f"| {fmt_cer(prev_cer)} → {fmt_cer(cur_cer)} | **{delta:+.3f}** |"
            )
    lines.append("")

    # ── Section 4: Failed Details ──
    lines.append(f"{h}# 4. 失败 Case 明细")
    lines.append("")

    failed = [e for e in pipeline["entries"] if not e["passed"]]
    failed.sort(key=lambda e: -e["cer"])

    if not failed:
        lines.append("*全部通过！*")
    else:
        lines.append(f"共 {len(failed)} 条失败：")
        lines.append("")
        lines.append("| # | ID | 类别 | CER | 期望文本 | 实际输出 |")
        lines.append("|---|-----|------|:---:|---------|---------|")
        for i, e in enumerate(failed, 1):
            lines.append(
                f"| {i} | {e['id']} | {e['category']} | {fmt_cer(e['cer'])} "
                f"| {truncate(e['expected_text'])} | {truncate(e['actual_text'])} |"
            )
    lines.append("")

    # ── Category Breakdown ──
    lines.append(f"{h}# 5. 按类别 CER 汇总")
    lines.append("")

    categories: dict[str, list[dict]] = {}
    for e in pipeline["entries"]:
        categories.setdefault(e["category"], []).append(e)

    lines.append("| 类别 | 条数 | 平均 CER | CER=0 | CER≤0.10 | CER>0.10 |")
    lines.append("|------|:----:|:-------:|:-----:|:--------:|:--------:|")

    for cat in sorted(categories):
        entries = categories[cat]
        n = len(entries)
        cers = [e["cer"] for e in entries]
        avg = sum(cers) / n if n else 0
        perfect = sum(1 for c in cers if c < 0.001)
        low = sum(1 for c in cers if c <= 0.10)
        high = sum(1 for c in cers if c > 0.10)
        lines.append(f"| {cat} | {n} | {fmt_cer(avg)} | {perfect} | {low} | {high} |")

    lines.append("")
    return lines


def generate_report(
    current_data: dict,
    previous_data: dict | None,
) -> str:
    """Generate full Markdown report."""
    lines: list[str] = []

    suite = current_data.get("suite", "unknown")
    ts = current_data.get("timestamp", "")
    commit = current_data.get("git_commit", "unknown")
    branch = current_data.get("git_branch", "unknown")

    # Title
    suite_label = "E2E" if suite == "e2e" else "Benchmark" if suite == "benchmark" else suite
    lines.append(f"# ASR 测试报告: {suite_label}")
    lines.append("")
    lines.append(f"*生成时间: {ts}*  |  *Commit: {commit} ({branch})*")
    if previous_data:
        prev_ts = previous_data.get("timestamp", "")
        prev_commit = previous_data.get("git_commit", "unknown")
        lines.append(f"*对比基准: {prev_ts} ({prev_commit})*")
    lines.append("")
    lines.append("---")
    lines.append("")

    cur_pipelines = get_pipelines(current_data)
    prev_pipelines = get_pipelines(previous_data) if previous_data else []
    prev_by_name = {p["pipeline_name"]: p for p in prev_pipelines}

    for pipeline in cur_pipelines:
        prev_pipeline = prev_by_name.get(pipeline["pipeline_name"])
        heading = 2 if len(cur_pipelines) > 1 else 1
        lines.extend(generate_pipeline_report(pipeline, prev_pipeline, heading_level=heading))
        lines.append("---")
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="ASR 测试报告生成器")
    parser.add_argument("--current", required=True, help="当前测试结果 JSON 文件")
    parser.add_argument("--previous", default=None, help="上次测试结果 JSON 文件（用于对比）")
    parser.add_argument("-o", "--output", default=None, help="输出 Markdown 文件路径（默认输出到 stdout）")
    args = parser.parse_args()

    current_data = load_json(args.current)
    previous_data = load_json(args.previous) if args.previous else None

    report = generate_report(current_data, previous_data)

    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(report, encoding="utf-8")
        print(f"[generate_test_report] 报告已保存到: {args.output}", file=sys.stderr)
    else:
        print(report)


if __name__ == "__main__":
    main()
