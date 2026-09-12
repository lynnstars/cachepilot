#!/usr/bin/env python3
"""scanner/scan.py 的自动化测试：只读保证、双语输出、schema v2 解析。"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN = ROOT / "scanner" / "scan.py"
RULES = ROOT / "rules" / "cleanable_rules.json"


class ScanPyTests(unittest.TestCase):

    def run_scan(self, *args, env=None):
        e = dict(os.environ)
        e.pop("CACHEPILOT_LANG", None)
        e.pop("LANG", None); e.pop("LC_ALL", None); e.pop("LC_MESSAGES", None)
        if env:
            e.update(env)
        return subprocess.run([sys.executable, str(SCAN), *args],
                              capture_output=True, text=True, env=e, timeout=600)

    def test_rules_schema_v2_bilingual(self):
        doc = json.loads(RULES.read_text())
        self.assertEqual(doc["schema_version"], 2)
        self.assertGreaterEqual(len(doc["rules"]), 18)
        for r in doc["rules"]:
            self.assertIn("en", r["name"], r["id"])
            self.assertIn("zh", r["name"], r["id"])
            self.assertIn("zh", r["why"], r["id"])
            self.assertIn(r["risk"], ("low", "medium", "high"), r["id"])
            self.assertTrue(r["paths"], r["id"])
            if r.get("show_only"):
                self.assertFalse(r.get("default_clean", False), r["id"])

    def test_no_rule_targets_trash(self):
        doc = json.loads(RULES.read_text())
        for r in doc["rules"]:
            for p in r["paths"]:
                self.assertFalse(p.rstrip("/").endswith(".Trash"), f"{r['id']} targets the Trash folder")

    def test_language_defaults(self):
        # zh 环境 → 中文；其他语言/无设置 → 英文
        zh = self.run_scan("--json", env={"LANG": "zh_CN.UTF-8"})
        self.assertEqual(json.loads(zh.stdout)["lang"], "zh")
        ja = self.run_scan("--json", env={"LANG": "ja_JP.UTF-8"})
        self.assertEqual(json.loads(ja.stdout)["lang"], "en")
        none = self.run_scan("--json")
        self.assertEqual(json.loads(none.stdout)["lang"], "en")
        forced = self.run_scan("--json", "--lang", "zh")
        self.assertEqual(json.loads(forced.stdout)["lang"], "zh")

    def test_text_output_is_localized(self):
        zh = self.run_scan("--lang", "zh", env={"LANG": "zh_CN.UTF-8"})
        self.assertIn("只读", zh.stdout)
        en = self.run_scan("--lang", "en", env={"LANG": "en_US.UTF-8"})
        self.assertIn("read-only", en.stdout.lower())

    def test_trash_flag_is_refused(self):
        r = self.run_scan("--trash", "--lang", "en")
        self.assertEqual(r.returncode, 2)
        self.assertIn("does not clean", r.stdout)

    def test_scan_is_read_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = Path(tmp) / "keepme"
            probe.mkdir()
            (probe / "file.bin").write_bytes(b"x" * 4096)
            rules = Path(tmp) / "rules.json"
            rules.write_text(json.dumps({
                "schema_version": 2,
                "categories": {"package-manager": {"en": "c", "zh": "c"}},
                "rules": [{
                    "id": "probe", "category": "package-manager", "tool": "probe",
                    "name": {"en": "probe", "zh": "探针"}, "risk": "low",
                    "paths": [str(probe)], "min_size_mb": 0,
                    "why": {"en": "w", "zh": "w"}, "official_cmd": {"en": "x", "zh": "x"},
                    "default_clean": True,
                }],
            }))
            before = sorted(p.name for p in probe.iterdir())
            r = self.run_scan("--rules", str(rules), "--json", "--lang", "en")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("probe", r.stdout)
            self.assertEqual(before, sorted(p.name for p in probe.iterdir()), "scan.py must not touch files")
            self.assertTrue((probe / "file.bin").exists())


if __name__ == "__main__":
    unittest.main()
