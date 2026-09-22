#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Recall.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$PROJECT_DIR/.build/module-cache"
bash "$PROJECT_DIR/scripts/swiftc-local.sh" -parse-as-library -O \
  "$PROJECT_DIR/apps/recall/Core.swift" "$PROJECT_DIR/apps/recall/ClipboardDiscovery.swift" "$PROJECT_DIR/apps/recall/Model.swift" \
  "$PROJECT_DIR/apps/recall/Views.swift" "$PROJECT_DIR/apps/recall/Main.swift" \
  -o "$APP_DIR/Contents/MacOS/Recall"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Recall</string>
<key>CFBundleIdentifier</key><string>local.jev.recall</string>
<key>CFBundleName</key><string>随手贴</string>
<key>CFBundleDisplayName</key><string>随手贴</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
printf '%s\n' "$PROJECT_DIR" > "$APP_DIR/Contents/Resources/workspace.txt"
codesign --force --sign - "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
