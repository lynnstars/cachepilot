#!/usr/bin/env python3
"""CachePilot 只读预览扫描器（scanner/scan.py）。

v0.4 起：真正的清理动作由 Swift 内核的 `cachepilot` CLI 负责（带清单、编号授权、
暂存/撤销/彻底释放与安全护栏）。本脚本保留为**只读预览**——它不会、也不能移动任何文件。

语言：默认跟随系统语言（zh* → 中文，其他语言 → 英文），可用 --lang zh|en 覆盖。
用法:
  python3 scanner/scan.py [--json] [--lang zh|en] [--rules PATH]
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DEFAULT_RULES = BASE / "rules" / "cleanable_rules.json"
HOME = Path.home()

CAT_DISPLAY = {
    "package-manager": {"en": "Package manager caches", "zh": "包管理器缓存"},
    "ai-tools": {"en": "AI tool residue", "zh": "AI 工具残留"},
    "containers": {"en": "Containers & virtualization", "zh": "容器与虚拟化"},
    "browser-automation": {"en": "Browser automation", "zh": "浏览器自动化"},
    "build-artifacts": {"en": "Build artifacts", "zh": "工程构建产物"},
    "app-caches": {"en": "App caches (whitelisted)", "zh": "应用缓存（白名单）"},
    "general": {"en": "General", "zh": "通用"},
}

TEXT = {
    "header": {
        "en": "CachePilot read-only preview — no file is ever moved or deleted here",
        "zh": "CachePilot 只读预览 —— 不会移动或删除任何文件",
    },
    "totals": {"en": "Reclaimable total: %s (suggested: %s)",
               "zh": "可回收合计：%s（建议项：%s）"},
    "readonly": {"en": "Read-only scan. Cleaning is done by the `cachepilot` CLI (numbered authorization, Trash-first, undoable).",
                 "zh": "本次为只读扫描。真正的清理请用 `cachepilot` CLI（按编号授权、先入废纸篓、可撤销）。"},
    "noitems": {"en": "Nothing found above the current thresholds.",
                "zh": "当前阈值下没有扫描到可清理项。"},
    "why": {"en": "why safe: %s", "zh": "为什么可删：%s"},
    "cmd": {"en": "official command: %s", "zh": "官方命令：%s"},
    "cleaning_refused": {"en": "This preview script does not clean anything. Use `cachepilot stage --select 1,3-5` (Swift CLI).",
                         "zh": "本预览脚本不执行清理。请用 `cachepilot stage --select 1,3-5`（Swift CLI）。"},
    "suggested": {"en": "suggested", "zh": "建议清"},
    "optional": {"en": "optional", "zh": "看情况"},
    "showonly": {"en": "display only", "zh": "仅展示"},
}

RISK = {"low": {"en": "low", "zh": "低"}, "medium": {"en": "medium", "zh": "中"}, "high": {"en": "high", "zh": "高"}}


def resolve_lang(cli_lang=None):
    """zh* → 中文；其他任何语言 → 英文（与 App/CLI 的规则一致）。"""
    for candidate in (cli_lang, os.environ.get("CACHEPILOT_LANG")):
        if candidate:
            return "zh" if candidate.lower().startswith("zh") else "en"
    for env_name in ("LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(env_name, "")
        if v:
            low = v.lower()
            if low.startswith("zh"):
                return "zh"
            # 其他显式设置的区域（如 ja_JP.UTF-8 / de_DE）→ 英文
            return "en"
    return "en"


def t(key, lang, *args):
    s = TEXT[key][lang]
    return s % args if args else s


def localized(value, lang):
    """规则里的 {en, zh} 或纯字符串"""
    if isinstance(value, dict):
        return value.get(lang) or value.get("en") or ""
    return value or ""


def expand(p: str) -> Path:
    return Path(p.replace("~", str(HOME)))


def du_kb(path: Path) -> int:
    if not path.exists():
        return 0
    try:
        out = subprocess.run(["du", "-sk", str(path)], capture_output=True, text=True, timeout=120).stdout
        return int(out.split("\t")[0]) if out.strip() else 0
    except Exception:
        return 0


def load_rules(path: Path):
    return json.loads(path.read_text())


def scan(rules_path: Path, lang: str) -> dict:
    doc = load_rules(rules_path)
    results = []
    for r in doc.get("rules", []):
        total_kb = 0
        found = []
        for raw in r.get("paths", []):
            p = expand(raw)
            kb = du_kb(p)
            if kb > 0:
                found.append({"path": str(p), "kb": kb})
                total_kb += kb
        min_mb = r.get("min_size_mb", 50)
        if total_kb < min_mb * 1024 or not found:
            continue
        results.append({
            "id": r["id"],
            "tool": r["tool"],
            "name": localized(r.get("name"), lang),
            "category": r.get("category"),
            "risk": r.get("risk"),
            "kb": total_kb,
            "found": found,
            "why": localized(r.get("why"), lang),
            "official_cmd": localized(r.get("official_cmd"), lang),
            "default_clean": r.get("default_clean", True),
            "show_only": r.get("show_only", False),
        })
    results.sort(key=lambda x: -x["kb"])
    return {"schema_version": doc.get("schema_version", 1), "lang": lang, "results": results}


def fmt(kb: float) -> str:
    return f"{kb / 1048576:,.2f} GB"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--lang", choices=["zh", "en"], help="覆盖语言（默认跟随系统语言）")
    ap.add_argument("--rules", default=str(DEFAULT_RULES))
    ap.add_argument("--trash", action="store_true",
                    help="已废弃：本脚本不再执行任何清理（只读预览）")
    args = ap.parse_args()

    lang = resolve_lang(args.lang)
    if args.trash:
        print(t("cleaning_refused", lang))
        return 2

    data = scan(Path(args.rules), lang)
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=1))
        return 0

    by_cat = {}
    for it in data["results"]:
        by_cat.setdefault(it["category"], []).append(it)

    total = 0
    suggested = 0
    line = "=" * 72
    print(line)
    print(t("header", lang))
    print(line)
    if not data["results"]:
        print(t("noitems", lang))
    for cat in sorted(by_cat, key=lambda c: -sum(i["kb"] for i in by_cat[c])):
        items = by_cat[cat]
        cat_sum = sum(i["kb"] for i in items)
        total += cat_sum
        name = CAT_DISPLAY.get(cat, {}).get(lang, cat)
        print(f"\n{'-'*72}\n{name}  ·  {fmt(cat_sum)}  ({len(items)})\n{'-'*72}")
        for it in items:
            if it["show_only"]:
                flag = t("showonly", lang)
            elif it["default_clean"]:
                flag = t("suggested", lang)
                suggested += it["kb"]
            else:
                flag = t("optional", lang)
            print(f"\n  [{flag}] {it['name']}  ——  {fmt(it['kb'])}  ({RISK.get(it['risk'], {}).get(lang, it['risk'])})")
            for f in it["found"]:
                print(f"        {f['path']}  ({fmt(f['kb'])})")
            print("        " + t("why", lang, it["why"]))
            if it["official_cmd"]:
                print("        " + t("cmd", lang, it["official_cmd"]))
    print(f"\n{line}")
    print(t("totals", lang, fmt(total), fmt(suggested)))
    print(t("readonly", lang))
    print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
