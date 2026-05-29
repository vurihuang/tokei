#!/bin/bash
# 构建并打包成 .app(无需 Xcode,仅 SwiftPM)。产物:./Tokei.app
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Tokei.app"
BIN="$(swift build -c release --show-bin-path)/Tokei"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tokei"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tokei</string>
    <key>CFBundleDisplayName</key><string>Tokei</string>
    <key>CFBundleIdentifier</key><string>local.tokei</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Tokei</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built: $(pwd)/$APP"
