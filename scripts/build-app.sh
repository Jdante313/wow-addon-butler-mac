#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="魔兽插件管家"
APP="$DIST/$APP_NAME.app"
BUILD="$ROOT/build"
VERSION="2.1.8"

NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
NPM_BIN="${NPM_BIN:-$(command -v npm || true)}"
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "找不到 Node.js。请安装 Node 20+，或用 NODE_BIN=/path/to/node 指定。" >&2
  exit 1
fi

if [[ ! -d "$ROOT/app/node_modules/adm-zip" ]]; then
  if [[ -z "$NPM_BIN" || ! -x "$NPM_BIN" ]]; then
    echo "缺少 app/node_modules/adm-zip，且找不到 npm。请先执行 cd app && npm install。" >&2
    exit 1
  fi
  echo "• 安装应用依赖"
  (cd "$ROOT/app" && "$NPM_BIN" install --omit=dev)
fi

echo "• 清理旧产物"
rm -rf "$APP" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/AppIcon.iconset"

echo "• 复制应用文件"
rsync -a \
  --exclude 'test' \
  --exclude '.DS_Store' \
  "$ROOT/app/" "$APP/Contents/Resources/app/"
rm -rf "$APP/Contents/Resources/app/test"

echo "• 复制 Node 运行时"
mkdir -p "$APP/Contents/Resources/runtime"
cp "$NODE_BIN" "$APP/Contents/Resources/runtime/node"
chmod +x "$APP/Contents/Resources/runtime/node"

echo "• 生成应用图标"
ICON_SRC="$ROOT/app/assets/icon.png"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$ICON_SRC" --out "$BUILD/AppIcon.iconset/tmp-$size.png" >/dev/null
done
cp "$BUILD/AppIcon.iconset/tmp-16.png" "$BUILD/AppIcon.iconset/icon_16x16.png"
cp "$BUILD/AppIcon.iconset/tmp-32.png" "$BUILD/AppIcon.iconset/icon_16x16@2x.png"
cp "$BUILD/AppIcon.iconset/tmp-32.png" "$BUILD/AppIcon.iconset/icon_32x32.png"
cp "$BUILD/AppIcon.iconset/tmp-64.png" "$BUILD/AppIcon.iconset/icon_32x32@2x.png"
cp "$BUILD/AppIcon.iconset/tmp-128.png" "$BUILD/AppIcon.iconset/icon_128x128.png"
cp "$BUILD/AppIcon.iconset/tmp-256.png" "$BUILD/AppIcon.iconset/icon_128x128@2x.png"
cp "$BUILD/AppIcon.iconset/tmp-256.png" "$BUILD/AppIcon.iconset/icon_256x256.png"
cp "$BUILD/AppIcon.iconset/tmp-512.png" "$BUILD/AppIcon.iconset/icon_256x256@2x.png"
cp "$BUILD/AppIcon.iconset/tmp-512.png" "$BUILD/AppIcon.iconset/icon_512x512.png"
cp "$BUILD/AppIcon.iconset/tmp-1024.png" "$BUILD/AppIcon.iconset/icon_512x512@2x.png"
rm -f "$BUILD"/AppIcon.iconset/tmp-*.png
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "• 编译原生外壳"
ARCH="$(uname -m)"
swiftc -O -whole-module-optimization \
  -target "${ARCH}-apple-macos13.5" \
  -framework Cocoa -framework WebKit \
  "$ROOT/native/main.swift" \
  -o "$APP/Contents/MacOS/WowAddonButler"

echo "• 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>WowAddonButler</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.personal.wowaddonbutler</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.5</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>个人使用工具 · 魔兽世界插件管家</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><false/>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "• 签名（ad-hoc）"
codesign --force --sign - --timestamp=none "$APP/Contents/Resources/runtime/node" >/dev/null
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/WowAddonButler" >/dev/null
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "• 打包 zip"
ZIP="$DIST/$APP_NAME-$VERSION-macOS-$(uname -m).zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo ""
echo "完成："
du -sh "$APP" "$ZIP" | sed 's/^/  /'
echo "  应用：$APP"
echo "  压缩包：$ZIP"
