#!/bin/bash
# CachePilot 全量自动化测试
#   1) Swift 单元测试（语言解析/规则库/安全护栏/重复与冗余检测/暂存-撤销-释放/清单编号）
#   2) CLI 端到端测试（plan → stage → release / undo、护栏、系统语言切换）
#   3) Python 预览脚本测试（只读保证、双语输出、schema v2）
# 用法: bash scripts/run-tests.sh        （仓库根目录）
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
FAILED=0
PASS=0

banner() { echo; echo "════════════════════════════════════════════════════════════"; echo "$1"; echo "════════════════════════════════════════════════════════════"; }
banner "CachePilot test suite"

# ─────────────────────────────────────────────────────────────
echo
echo "▶ 1/3 Swift unit tests"
# swiftc 只允许名为 main.swift 的文件带顶层代码 → 复制一份再编译
mkdir -p app/build
cp app/Tests/run-tests.swift app/build/main.swift
( cd app && CORE=$(ls Sources/CachePilot/*.swift | grep -v -e CachePilotApp.swift -e ContentView.swift) && \
  swiftc -swift-version 5 $CORE build/main.swift -o build/cachepilot-tests 2>&1 | grep -E "error:" ) || true
if [ ! -x app/build/cachepilot-tests ]; then
  echo "✗ Swift 测试编译失败"; exit 1
fi
( cd app && ./build/cachepilot-tests ) || FAILED=1

# ─────────────────────────────────────────────────────────────
echo
echo "▶ 2/3 CLI end-to-end tests"
bash app/scripts/build-cli.sh >/dev/null 2>&1 || { echo "✗ CLI 构建失败"; exit 1; }
CLI="$ROOT/app/build/bin/cachepilot"

# 沙箱放在 home 下：/var/folders(TMPDIR) 命中系统黑名单，不能用来构造场景
SB="$HOME/Library/Caches/CachePilotTests-$$"
FIX="$SB/home"
rm -rf "$SB"
mkdir -p "$FIX/假缓存" "$FIX/.Trash" "$FIX/大文件" "$FIX/重复" "$SB/data"
dd if=/dev/zero of="$FIX/假缓存/blob.bin" bs=1m count=3 2>/dev/null
dd if=/dev/zero of="$FIX/大文件/电影 4K.mov" bs=1m count=4 2>/dev/null
dd if=/dev/zero of="$FIX/大文件/电影 4K-最新(1).mov" bs=1m count=5 2>/dev/null   # 同名不同大小 → 冗余版本
dd if=/dev/zero of="$FIX/重复/安装包.zip" bs=1m count=2 2>/dev/null
cp "$FIX/重复/安装包.zip" "$FIX/重复/安装包-副本.zip"                              # 内容一致 → 重复文件

cat > "$SB/rules.json" <<EOF
{"schema_version":2,
 "categories":{"package-manager":{"en":"Package manager caches","zh":"包管理器缓存"}},
 "rules":[{"id":"test-cache","category":"package-manager","tool":"test",
   "name":{"en":"Test cache","zh":"测试缓存"},"risk":"low",
   "paths":["$FIX/假缓存"],"min_size_mb":1,
   "why":{"en":"rebuildable","zh":"可重建"},
   "official_cmd":{"en":"test clean","zh":"test clean"},"default_clean":true},
  {"id":"protected-check","category":"package-manager","tool":"sys",
   "name":{"en":"Protected path check","zh":"受保护路径检查"},"risk":"low",
   "paths":["/Applications"],"min_size_mb":0,
   "why":{"en":"must be refused","zh":"必须被拒绝"},
   "official_cmd":{"en":"-","zh":"-"},"default_clean":true}]}
EOF

export CACHEPILOT_RULES="$SB/rules.json"
export CACHEPILOT_TRASH_DIR="$FIX/.Trash"
export CACHEPILOT_DATA_DIR="$SB/data"
unset LANG LC_ALL LC_MESSAGES 2>/dev/null || true

ok()  { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad() { FAILED=1; echo "  ✗ $1"; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing: $2)"; fi }
absent() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi }

# 按 id 拿编号（编号授权是产品契约，测试也必须走同一条路）
idx_of() {
  "$CLI" plan --mode "${2:-all}" --min-size "${3:-1MB}" --dup-min-size 1MB --version-min-size 1MB --root "$FIX" --json 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((e['index'] for e in d['entries'] if e['id']=='$1'),''))"
}

echo "  ── 报告与双语 ──"
OUT="$("$CLI" plan --mode all --min-size 1MB --dup-min-size 1MB --version-min-size 1MB --root "$FIX" --lang en 2>&1)"
has "$OUT" "Cache & dependency rules" "EN: cache section"
has "$OUT" "Large files (by size)" "EN: large-file section"
has "$OUT" "Duplicate files" "EN: duplicate section"
has "$OUT" "Redundant versions" "EN: redundant-version section"
has "$OUT" "Authorize with --select" "EN: numbered-authorization hint"
has "$OUT" "Test cache" "EN: rule title from the rule library"

OUT_ZH="$("$CLI" plan --mode all --min-size 1MB --dup-min-size 1MB --version-min-size 1MB --root "$FIX" --lang zh 2>&1)"
has "$OUT_ZH" "缓存与依赖规则" "ZH: cache section"
has "$OUT_ZH" "大文件" "ZH: large-file section"
has "$OUT_ZH" "重复文件" "ZH: duplicate section"
has "$OUT_ZH" "冗余版本" "ZH: redundant-version section"
has "$OUT_ZH" "编号在本次清单内固定" "ZH: numbered-authorization hint"
has "$OUT_ZH" "测试缓存" "ZH: rule title translated from the rule library"
absent "$OUT_ZH" "Cache & dependency rules" "ZH: no leftover English section titles"

echo "  ── 系统语言自动切换（zh* → 中文，其他语言 → 英文）──"
OUT_JA="$(env -u CACHEPILOT_LANG "$CLI" -AppleLanguages '(ja-JP)' plan --mode cache --root "$FIX" 2>&1)"
has "$OUT_JA" "Cache & dependency rules" "system language ja-JP → English"
OUT_DE="$(env -u CACHEPILOT_LANG "$CLI" -AppleLanguages '(de-DE)' plan --mode cache --root "$FIX" 2>&1)"
has "$OUT_DE" "Cache & dependency rules" "system language de-DE → English"
OUT_SYS_ZH="$(env -u CACHEPILOT_LANG "$CLI" -AppleLanguages '(zh-Hans-CN)' plan --mode cache --root "$FIX" 2>&1)"
has "$OUT_SYS_ZH" "缓存与依赖规则" "system language zh-Hans-CN → Chinese"
OUT_SYS_ZHTW="$(env -u CACHEPILOT_LANG "$CLI" -AppleLanguages '(zh-Hant-TW)' plan --mode cache --root "$FIX" 2>&1)"
has "$OUT_SYS_ZHTW" "缓存与依赖规则" "system language zh-Hant-TW → Chinese"

echo "  ── plan 落盘 + 暂存 ──"
[ -f "$SB/data/plans/latest.json" ] && ok "plan saved to latest.json" || bad "plan saved to latest.json"
IDX_CACHE="$(idx_of test-cache all 1MB)"
[ -n "$IDX_CACHE" ] && ok "resolved test-cache index = $IDX_CACHE" || bad "resolve test-cache index"
OUT_STAGE="$("$CLI" stage --select "$IDX_CACHE" --lang en 2>&1)"
has "$OUT_STAGE" "NO space freed yet" "stage tells the user space is NOT freed yet"
[ -d "$FIX/假缓存" ] && bad "cache dir should have been staged" || ok "cache dir moved out"
ls "$FIX/.Trash" | grep -q "假缓存" && ok "staged item visible in the Trash (recoverable)" || bad "staged item in Trash"
"$CLI" doctor --lang en | grep -q "staged in the Trash" && ok "doctor reports pending staged bytes" || bad "doctor staged banner"

echo "  ── 彻底释放（真正回收空间）──"
OUT_NOCONF="$("$CLI" release --lang en 2>&1)"; RC=$?
has "$OUT_NOCONF" "confirm-irreversible" "release without the flag is refused"
[ $RC -ne 0 ] && ok "release without the flag exits non-zero" || bad "release without the flag exit code"
OUT_REL="$("$CLI" release --confirm-irreversible --lang en 2>&1)"
has "$OUT_REL" "freed" "release reports freed bytes"
[ -d "$FIX/假缓存" ] && bad "cache dir still present after release" || ok "released item really deleted (space reclaimed)"
"$CLI" manifests --lang en | grep -q "released" && ok "manifest recorded as released" || bad "manifest state"

echo "  ── 撤销（暂存 → 还原）──"
mkdir -p "$FIX/假缓存"; dd if=/dev/zero of="$FIX/假缓存/blob.bin" bs=1m count=3 2>/dev/null
IDX_CACHE="$(idx_of test-cache all 1MB)"
"$CLI" stage --select "$IDX_CACHE" >/dev/null 2>&1
[ -d "$FIX/假缓存" ] && bad "undo test: staging failed" || ok "staged for the undo test"
"$CLI" undo >/dev/null 2>&1
[ -f "$FIX/假缓存/blob.bin" ] && ok "undo restored the directory to its original path" || bad "undo restored the directory"

echo "  ── 安全护栏 ──"
IDX_PROT="$(idx_of protected-check all 1MB)"
if [ -n "$IDX_PROT" ]; then
  OUT_GUARD="$("$CLI" stage --select "$IDX_PROT" --lang en 2>&1)"
  has "$OUT_GUARD" "Refused" "protected path (/Applications) is refused"
  [ -d /Applications ] && ok "/Applications untouched" || bad "/Applications untouched"
else
  echo "  · protected-path rule not present in plan (skipped)"
fi

echo "  ── dry-run ──"
IDX_CACHE="$(idx_of test-cache all 1MB)"
OUT_DRY="$("$CLI" stage --select "$IDX_CACHE" --dry-run --lang en 2>&1)"
has "$OUT_DRY" "dry run" "dry-run announces itself"
[ -d "$FIX/假缓存" ] && ok "dry-run moved nothing" || bad "dry-run moved something"

echo "  ── 只读预览脚本已不再执行清理 ──"
python3 scanner/scan.py --trash >/dev/null 2>&1
[ $? -eq 2 ] && ok "scan.py refuses to clean (exit 2)" || bad "scan.py cleaning refusal"

rm -rf "$SB"

# ─────────────────────────────────────────────────────────────
echo
echo "▶ 3/3 Python preview script tests (scanner/scan.py)"
python3 -m unittest discover -s tests -p "test_*.py" 2>&1 | tail -6 || FAILED=1

banner "RESULT: $PASS CLI assertions passed · $([ $FAILED -eq 0 ] && echo 'ALL TESTS PASSED ✅' || echo 'SOME TESTS FAILED ❌')"
exit $FAILED
