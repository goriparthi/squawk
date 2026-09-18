#!/bin/bash
# Assembles dist/Squawk.app. The hook binary ships inside the bundle so the app
# and the hook can never drift apart on the wire protocol.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build --package-path app -c release

app="dist/Squawk.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"

cp app/.build/release/Squawk "$app/Contents/MacOS/Squawk"
cp app/.build/release/squawk-hook "$app/Contents/Helpers/squawk-hook"
cp app/Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --deep --sign - "$app" 2>/dev/null || echo "note: ad hoc signing skipped"
echo "built $app"
