#!/usr/bin/env bash
# Builds build/Soapcap.app.
# Signs ad hoc by default. Set SOAPCAP_SIGN_IDENTITY to a stable local code
# signing identity to keep macOS privacy grants across rebuilds, or to a
# Developer ID Application identity for a build to hand to notarize.sh.
# SOAPCAP_BUNDLE_ID and SOAPCAP_OUT give a build its own identifier and
# folder, so that one signed another way can sit beside the usual one with
# permissions of its own.
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$here"

# Marketing version from VERSION; build number is the commit count, so it
# rises with every commit (CFBundleVersion must only ever increase).
version=$(tr -d '[:space:]' < VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release
./engine.sh
identity="${SOAPCAP_SIGN_IDENTITY:--}"
id="${SOAPCAP_BUNDLE_ID:-com.jukenzie.soapcap}"
app="${SOAPCAP_OUT:-$here/build}/Soapcap.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp Assets/soapcap.icns "$app/Contents/Resources/soapcap.icns"
# The note prompts are data files; the app reads them from its Resources.
cp -R Sources/SoapcapNote/Resources/prompts "$app/Contents/Resources/prompts"
bin=$(swift build -c release --show-bin-path)
cp "$bin/Soapcap" "$app/Contents/MacOS/Soapcap"
# The note-model engine: started by the app for a draft, never run by hand.
cp "$here/.build/engine/llama-server" "$app/Contents/Helpers/llama-server"
# Resource bundles of the packages the app links (one holds the Metal library
# the de-identification model runs on). They are looked up in Resources.
for bundle in "$bin"/*.bundle; do
  case "$(basename "$bundle")" in soapcap-swift_SoapcapNote.bundle) continue ;; esac  # its prompts are copied above
  [ -f "$bundle/Contents/Info.plist" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
# Without the Metal library the app quits the first time it de-identifies,
# so a build that lacks it is not worth producing.
if [ ! -f "$app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" ]; then
  echo "build.sh: the Metal library (mlx-swift_Cmlx.bundle) is missing from $bin" >&2
  exit 1
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Soapcap</string>
  <key>CFBundleIdentifier</key><string>$id</string>
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
# Every build runs under the hardened runtime, as a notarized one must, so
# that what it forbids shows up here first. The microphone needs the
# entitlement. Apple's timestamp is only wanted on a build for release.
case "$identity" in "Developer ID Application"*) stamp=--timestamp ;; *) stamp=--timestamp=none ;; esac
# Code inside the app is signed first; the app's signature then covers it.
codesign --force --options runtime $stamp --sign "$identity" --identifier "$id.llama-server" "$app/Contents/Helpers/llama-server"
codesign --force --options runtime $stamp --sign "$identity" --identifier "$id" \
  --entitlements Assets/Soapcap.entitlements "$app"
echo "Built $app"
echo "Run: open \"$app\""
