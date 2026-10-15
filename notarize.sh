#!/usr/bin/env bash
# Has Apple notarize a built Soapcap.app and attaches the ticket to it, so
# that it opens on another Mac without a warning. This uploads the app to
# Apple. Usage: notarize.sh [APP]   (default build/Soapcap.app)
# What is left is a zip to ship beside where the app was. The app itself is
# then removed, since the zip holds it, ticket and all, and a second copy
# would show up in Spotlight; unzip it to run it.
# The app must be signed with a Developer ID Application identity (see
# build.sh). Credentials come from a keychain profile made once with
#   xcrun notarytool store-credentials soapcap-notary --apple-id … --team-id …
# SOAPCAP_NOTARY_PROFILE names a different profile.
set -eu
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
app="${1:-$here/build/Soapcap.app}"
profile="${SOAPCAP_NOTARY_PROFILE:-soapcap-notary}"

die() { echo "notarize.sh: $*" >&2; exit 1; }
[ -d "$app" ] || die "no app at $app"
codesign -dvv "$app" 2>&1 | grep -q "^Authority=Developer ID Application" \
  || die "$app is not signed with a Developer ID Application identity"
codesign --verify --deep --strict "$app" || die "the app's signature doesn't verify"

zip="${app%.app}.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "==> Sending $(du -h "$zip" | cut -f1 | tr -d ' ') to Apple (usually a few minutes)"
result=$(xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait 2>&1) || true
echo "$result" | grep -E "^ *(id|status):" | tail -n 2
if ! echo "$result" | grep -q "status: Accepted"; then
  submission=$(echo "$result" | awk '/^ *id:/ {print $2; exit}')
  [ -n "$submission" ] && xcrun notarytool log "$submission" --keychain-profile "$profile" >&2 || true
  die "Apple did not accept it"
fi
xcrun stapler staple "$app"
# The zip was made before the ticket was attached; make it again to ship.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute -vv "$app"
echo "Notarized $app"
if pgrep -qf "$app/Contents/MacOS/"; then
  echo "Kept $app: it is running"
else
  rm -rf "$app"
  echo "Removed $app: the zip holds it"
fi
echo "To ship: $zip"
