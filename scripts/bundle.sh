#!/bin/bash
# 构建并打包 QwenGlasses.app（无需完整 Xcode，仅 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=QwenGlasses
OUT_DIR=build
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

BIN=".build/release/$APP_NAME"
[ -f "$BIN" ] || { echo "找不到构建产物 $BIN"; exit 1; }

echo "==> 组装 $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> ad-hoc 签名"
codesign --force --sign - --entitlements Resources/entitlements.plist "$APP_BUNDLE"

echo ""
echo "打包完成: $APP_BUNDLE"
echo "运行:     open $APP_BUNDLE"
echo "注意: ad-hoc 签名每次重新构建后，macOS 可能会重新请求蓝牙权限，属正常现象。"
