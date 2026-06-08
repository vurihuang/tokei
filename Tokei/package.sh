#!/bin/bash
# 构建并打包成 .app + .dmg(无需 Xcode,仅 SwiftPM)。
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Tokei.app"
BIN="$(swift build -c release --show-bin-path)/Tokei"
PROJ_DIR="$(dirname "$(pwd)")"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 二进制
cp "$BIN" "$APP/Contents/MacOS/Tokei"

# 打包 Python 脚本和配置到 Resources
cp "$PROJ_DIR/usage.30s.py" "$APP/Contents/Resources/"
[ -f "$PROJ_DIR/pricing.json" ] && cp "$PROJ_DIR/pricing.json" "$APP/Contents/Resources/"
[ -f "$PROJ_DIR/pricing_overrides.json" ] && cp "$PROJ_DIR/pricing_overrides.json" "$APP/Contents/Resources/"
[ -f "AppIcon.icns" ] && cp "AppIcon.icns" "$APP/Contents/Resources/"

# Info.plist
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tokei</string>
    <key>CFBundleDisplayName</key><string>Tokei</string>
    <key>CFBundleIdentifier</key><string>com.tokei.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Tokei</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
echo "Built: $(pwd)/$APP"

# 打包 DMG
if command -v hdiutil &>/dev/null; then
    DMG="Tokei.dmg"
    rm -f "$DMG"
    TMP_DMG="/tmp/tokei_dmg_$$"
    mkdir -p "$TMP_DMG"
    cp -R "$APP" "$TMP_DMG/"
    ln -s /Applications "$TMP_DMG/Applications"
    hdiutil create -volname "Tokei" -srcfolder "$TMP_DMG" -ov -format UDZO "$DMG" 2>/dev/null
    rm -rf "$TMP_DMG"
    echo "DMG: $(pwd)/$DMG"
fi
