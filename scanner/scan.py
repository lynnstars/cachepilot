#!/usr/bin/env python3
"""CachePilot scanner — 只读扫描预览，绝不删除任何文件。
用法: python3 scanner/scan.py [--json]
输出: 按类别分组的可清理候选清单 + 风险/建议/说明
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
RULES_FILE = BASE / "rules" / "cleanable_rules.json"
HOME = Path.home()

CAT_DISPLAY = {
    "package-manager": "📦 包管理器缓存",
    "ai-tools": "🤖 AI 工具残留",
    "browser-automation": "🌐 浏览器自动化",
    "build-artifacts": "🔨 工程构建产物",
    "app-caches": "🎬 应用缓存(白名单)",
    "general": "🧹 通用清理",
}
RISK = {"low": "🟢 低", "medium": "🟡 中", "high": "🔴 高"}


def expand(p: str) -> Path:
    p = p.replace("~", str(HOME))
    return Path(p)


def du_kb(path: Path) -> int:
    """du -sk 返回 KB；路径不存在返回 0"""
    if not path.exists():
        return 0
    try:
        out = subprocess.run(
            ["du", "-sk", str(path)],
            capture_output=True, text=True, timeout=120,
        ).stdout
        return int(out.split("\t")[0]) if out.strip() else 0
    except Exception:
        return 0


def scan() -> dict:
    rules = json.loads(RULES_FILE.read_text())["rules"]
    results = []
    for r in rules:
        total_kb = 0
        found = []
        for raw in r.get("paths", []):
            p = expand(raw)
            kb = du_kb(p)
            if kb > 0:
                found.append({"path": str(p), "kb": kb})
                total_kb += kb
        min_mb = r.get("min_size_mb", 50)
        if total_kb >= min_mb * 1024:
            results.append({
                "id": r["id"],
                "tool": r["tool"],
                "name": r["name"],
                "category": r["category"],
                "risk": r["risk"],
                "kb": total_kb,
                "found": found,
                "why": r.get("why", ""),
                "official_cmd": r.get("official_cmd", ""),
                "default_clean": r.get("default_clean", True),
                "show_only": r.get("show_only", False),
            })
    results.sort(key=lambda x: -x["kb"])
    return {"results": results}


def trash_paths(paths):
    """把路径移入 ~/.Trash（等价 Finder 移到废纸篓，可手动恢复）。
    仅用于 low 风险白名单项；冲突名自动加时间戳。"""
    moved = []
    trash = Path.home() / ".Trash"
    trash.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for raw in paths:
        p = expand(raw)
        if not p.exists():
            continue
        dest = trash / f"{p.name}-CachePilot-{stamp}"
        try:
            shutil.move(str(p), str(dest))
            moved.append((str(p), str(dest)))
        except Exception as e:
            print(f"  移动失败 {p}: {e}")
    return moved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--trash", action="store_true",
                    help="对『low 风险 & 默认建议清』的项执行移入废纸篓（默认 dry-run 不删）")
    ap.add_argument("--ids", nargs="*", help="仅处理指定规则 id（配合 --trash）")
    args = ap.parse_args()

    data = scan()
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=1))
        return

    if args.trash:
        eligible = [it for it in data["results"]
                    if it["risk"] == "low" and it["default_clean"] and not it.get("show_only")]
        if args.ids:
            eligible = [it for it in eligible if it["id"] in args.ids]
        if not eligible:
            print("没有符合条件的可执行项（需要 low 风险 + 默认建议清）。")
        else:
            print("== 执行移入废纸篓（可恢复）==")
            for it in eligible:
                gb = it["kb"] / 1048576
                moved = trash_paths([f["path"] for f in it["found"]])
                print(f"  {'✓' if moved else '-'} {it['name']} ({gb:,.2f} GB) -> ~/.Trash")
        print("重新扫描，显示剩余可清理项：\n")
        data = scan()

    by_cat = {}
    for it in data["results"]:
        by_cat.setdefault(it["category"], []).append(it)

    total = 0
    print("=" * 72)
    print("CachePilot 只读扫描预览 — 不删除任何文件")
    print("=" * 72)
    for cat in sorted(by_cat, key=lambda c: -sum(i["kb"] for i in by_cat[c])):
        items = by_cat[cat]
        cat_sum = sum(i["kb"] for i in items)
        total += cat_sum
        print(f"\n{'-'*72}\n{CAT_DISPLAY.get(cat, cat)}  合计 {cat_sum/1048576:,.2f} GB ({len(items)} 项)")
        print(f"{'-'*72}")
        for it in items:
            flag = "🔴 仅展示" if it.get("show_only") else ("🟢 建议清" if it["default_clean"] else "🟡 看情况")
            gb = it["kb"] / 1048576
            print(f"\n  [{flag}] {it['name']}  ——  {gb:,.2f} GB  风险{RISK[it['risk']]}")
            for f in it["found"]:
                print(f"        {f['path']}  ({f['kb']/1048576:,.2f} GB)")
            print(f"        为什么可删: {it['why']}")
            if it["official_cmd"]:
                print(f"        官方命令:   {it['official_cmd']}")
    print(f"\n{'='*72}")
    print(f"可识别可清理合计: {total/1048576:,.2f} GB（其中 🟢建议清 {sum(i['kb'] for c in by_cat for i in by_cat[c] if i['default_clean'] and not i.get('show_only'))/1048576:,.2f} GB）")
    if args.trash:
        print("上方为执行『移入废纸篓』后的剩余项。废纸篓内可手动恢复。")
    else:
        print("本次为只读扫描，未做任何删除。")
    print("=" * 72)


if __name__ == "__main__":
    main()
