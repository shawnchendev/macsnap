#!/bin/bash
# Assembles dist/Macsnap.app from release builds:
#   CFBundleExecutable = macsnap-menubar (resident menu bar)
#   Contents/MacOS/macsnap            (capture engine, launched by the menu bar)
# Usage: packaging/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*public static let version = "\(.*\)".*/\1/p' Sources/MacsnapCore/App/MacsnapApp.swift | head -n 1)
VERSION=${VERSION:-1.0.0}
BUNDLE_ID="com.macsnap.app"
# Signing identity: pass CODESIGN_IDENTITY="Apple Development: Name (TEAMID)"
# for a stable signature whose Screen Recording grant survives rebuilds.
# Default ad-hoc (-) works but every rebuild invalidates the TCC entry.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "==> warning: ad-hoc signing — re-grant Screen Recording after every rebuild (see README 'Permissions & rebuilding')"
fi
DIST="dist/Macsnap.app"
CONTENTS="$DIST/Contents"

echo "==> building release (macsnap $VERSION)"
swift build -c release

echo "==> assembling $DIST"
rm -rf "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/macsnap "$CONTENTS/MacOS/macsnap"
cp .build/release/macsnap-menubar "$CONTENTS/MacOS/macsnap-menubar"

# App icon (best effort; bundle works without one).
ICONSET="$(mktemp -d)/AppIcon.iconset"
if swift packaging/render-icon.swift "$ICONSET" >/dev/null 2>&1 \
    && iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null; then
    ICON_KEY="	<key>CFBundleIconFile</key>
	<string>AppIcon</string>"
    echo "==> app icon generated"
else
    ICON_KEY=""
    echo "==> warning: icon generation failed, continuing without one"
fi
rm -rf "$(dirname "$ICONSET")"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>macsnap</string>
	<key>CFBundleExecutable</key>
	<string>macsnap-menubar</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>macsnap</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
$ICON_KEY
</dict>
</plist>
EOF

echo "==> signing with '${CODESIGN_IDENTITY}'"
codesign --force -s "$CODESIGN_IDENTITY" "$CONTENTS/MacOS/macsnap" >/dev/null
codesign --force -s "$CODESIGN_IDENTITY" "$CONTENTS/MacOS/macsnap-menubar" >/dev/null
codesign --force -s "$CODESIGN_IDENTITY" "$DIST" >/dev/null 2>&1 || true

echo "==> done: $DIST"
ls -la "$CONTENTS/MacOS"
