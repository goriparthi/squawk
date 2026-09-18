#!/bin/bash
# Assembles dist/Squawk.app. The hook binary ships inside the bundle so the app
# and the hook can never drift apart on the wire protocol.
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
cd "$REPO_ROOT"

[ -f app/Resources/generated/Squawk.icns ] || scripts/render-icon.sh
swift build --package-path app -c release

app="dist/Squawk.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"

cp app/.build/release/Squawk "$app/Contents/MacOS/Squawk"
cp app/.build/release/squawk-hook "$app/Contents/Helpers/squawk-hook"
cp app/Resources/Info.plist "$app/Contents/Info.plist"
cp app/Resources/generated/Squawk.icns "$app/Contents/Resources/Squawk.icns"
cp app/Resources/generated/StatusTemplate.png "$app/Contents/Resources/StatusTemplate.png"
cp app/Resources/generated/StatusTemplate@2x.png "$app/Contents/Resources/StatusTemplate@2x.png"

# A Developer ID signature with the hardened runtime when one is available, so
# the same bundle can be notarized. Falls back to ad hoc for a local build.
identity="$(find_signing_identity)"
if [[ -n "$identity" ]]; then
    codesign --force --options runtime --timestamp \
        --entitlements app/Resources/Squawk.entitlements \
        --sign "$identity" "$app/Contents/Helpers/squawk-hook"
    codesign --force --options runtime --timestamp \
        --entitlements app/Resources/Squawk.entitlements \
        --sign "$identity" "$app"
    echo "signed with: $identity"
else
    codesign --force --deep --sign - "$app" 2>/dev/null || true
    echo "note: ad hoc signed, not distributable"
fi
echo "built $app"
