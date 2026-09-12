#!/bin/bash
# CachePilot 打包：swiftc 编译内核 + SwiftUI 界面 → .app bundle（无需完整 Xcode）
# 用法: bash scripts/make-app.sh   （在 app/ 目录下执行，或直接运行本脚本）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="build/CachePilot.app"
VERSION="0.4.0"
BUNDLE_ID="com.cachepilot.app"

# 内核（Foundation only）与界面（SwiftUI）分开编译，CLI 目标复用内核
CORE=$(ls Sources/CachePilot/*.swift | grep -v -e CachePilotApp.swift -e ContentView.swift)
GUI="Sources/CachePilot/CachePilotApp.swift Sources/CachePilot/ContentView.swift"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> 编译 SwiftUI app"
# shellcheck disable=SC2086
swiftc -swift-version 5 -O -parse-as-library \
  $CORE $GUI \
  -o "$APP_DIR/Contents/MacOS/CachePilot" \
  -framework SwiftUI

echo "==> 写入 Info.plist (version ${VERSION}, bundle id ${BUNDLE_ID})"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  Resources/Info.plist > "$APP_DIR/Contents/Info.plist"

echo "==> 拷贝规则库 JSON"
cp ../rules/cleanable_rules.json "$APP_DIR/Contents/Resources/cleanable_rules.json"

echo "==> ad-hoc 签名（含 bundle id，Info.plist 一起 sealed）"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "==> 校验签名"
codesign -dv "$APP_DIR" 2>&1 | sed -n '1,6p'

echo "==> 完成: $(pwd)/$APP_DIR"
echo "==> 运行: open $APP_DIR"
