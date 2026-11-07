#!/bin/zsh
# Wraps the ChartLab executable in an app bundle (unsigned, for running and testing on this Mac):
# Tools/make-app.sh [debug|release] → .build/ChartLab.app
set -euo pipefail
cd "${0:A:h}/.."
config="${1:-debug}"
swift build -c "$config" --product ChartLab
bin="$(swift build -c "$config" --show-bin-path)/ChartLab"
app=".build/ChartLab.app"
rm -rf "${app:?}"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/ChartLab"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>code.xocialize.ChartLab</string>
<key>CFBundleName</key><string>Chart Lab</string>
<key>CFBundleExecutable</key><string>ChartLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1 || true
echo "$PWD/$app"
