#!/usr/bin/env python3
"""2026-09-09 老板批准的 B/C 类清理（B1-B5, C1, C8, C9 移入废纸篓）。
C2-C7 保留。全部移 ~/.Trash 可手动恢复。"""
import shutil, time
from pathlib import Path

HOME = Path.home()
TRASH = HOME / ".Trash"
STAMP = time.strftime("%Y%m%d-%H%M%S")

APPROVED = [
    ("B1", HOME / "Downloads/AI中台+智能体平台讲解"),
    ("B2", HOME / "Downloads/osql-plugin-intellij"),
    ("B3", HOME / "Downloads/odpscmd_public"),
    ("B4", HOME / "Downloads/data.zip"),
    ("B5", HOME / "Downloads/feishu-backup"),
    ("C1", HOME / "Documents/Obsidian Vault/B2C电商业务部-创新产品线_backup.zip"),
    ("C8", HOME / "Downloads/昆仑网电生产运营系统项目-详细方案设计报告-内审优化版-功能模块方案分册2-20260303.docx"),
    ("C9", HOME / "Downloads/result_model.csv"),
]

total = 0
for tag, p in APPROVED:
    if not p.exists():
        print(f"{tag}: 不存在，跳过 {p}")
        continue
    dest = TRASH / f"{p.name}-CachePilot-{STAMP}"
    shutil.move(str(p), str(dest))
    total += 1
    print(f"{tag}: ✓ {p.name} -> ~/.Trash/{dest.name}")

print(f"\n完成，共移动 {total} 项到废纸篓（可手动恢复）")
