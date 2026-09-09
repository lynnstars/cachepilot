#!/bin/bash
# CachePilot 打包脚本：swiftc 编译 + 组装 .app bundle
set -e
cd "$(dirname "$0")/.."
APP_DIR="build/CachePilot.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> 编译 SwiftUI app"
swiftc -O -parse-as-library \
  Sources/CachePilot/*.swift \
  -o "$APP_DIR/Contents/MacOS/CachePilot" \
  -framework SwiftUI

echo "==> 写入 Info.plist"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "==> 拷贝规则库 JSON"
cp ../rules/cleanable_rules.json "$APP_DIR/Contents/Resources/cleanable_rules.json"

echo "==> 完成: $(pwd)/$APP_DIR"
echo "==> 运行: open $APP_DIR"
