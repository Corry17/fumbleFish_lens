#!/bin/bash
# 构建并打包「镜内 MirrorLens」为 .app 应用
set -e
cd "$(dirname "$0")"

echo "==> 编译 (release)..."
swift build -c release

APP="MirrorLens.app"
echo "==> 打包 $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MirrorLens "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/Info.plist"

echo "==> 签名 (ad-hoc)..."
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   (签名跳过)"

echo "==> 完成: $(pwd)/$APP"
