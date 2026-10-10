#!/usr/bin/env bash
# Builds build/Soapcap.app.
# Signs ad hoc by default. Set SOAPCAP_SIGN_IDENTITY to a stable local code
# signing identity to keep macOS privacy grants across rebuilds.
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$here"

# Marketing version from VERSION; build number is the commit count, so it
# rises with every commit (CFBundleVersion must only ever increase).
version=$(tr -d '[:space:]' < VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release
app="$here/build/Soapcap.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Assets/soapcap.icns "$app/Contents/Resources/soapcap.icns"
# The note prompts are data files; the app reads them from its Resources.
cp -R Sources/SoapcapNote/Resources/prompts "$app/Contents/Resources/prompts"
bin=$(swift build -c release --show-bin-path)
cp "$bin/Soapcap" "$app/Contents/MacOS/Soapcap"
# Resource bundles of the packages the app links (one holds the Metal library
# the de-identification model runs on). They are looked up in Resources.
for bundle in "$bin"/*.bundle; do
  case "$(basename "$bundle")" in soapcap-swift_*) continue ;; esac
  [ -f "$bundle/Contents/Info.plist" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Soapcap</string>
  <key>CFBundleIdentifier</key><string>local.soapcap.session</string>
  <key>CFBundleExecutable</key><string>Soapcap</string>
  <key>CFBundleIconFile</key><string>soapcap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Soapcap transcribes your microphone on-device during a session.</string>
</dict></plist>
PLIST
codesign --force --sign "${SOAPCAP_SIGN_IDENTITY:--}" --identifier local.soapcap.session "$app"
echo "Built $app"
echo "Run: open \"$app\""
