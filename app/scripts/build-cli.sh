#!/bin/bash
# 构建命令行版 cachepilot（与 App 共用同一内核）
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/bin"
mkdir -p "$OUT"
CORE=$(ls Sources/CachePilot/*.swift | grep -v -e CachePilotApp.swift -e ContentView.swift)

echo "==> 编译 cachepilot CLI"
# shellcheck disable=SC2086
swiftc -swift-version 5 -O $CORE Sources/CLI/main.swift -o "$OUT/cachepilot"

echo "==> 完成: $(pwd)/$OUT/cachepilot"
"$OUT/cachepilot" version
