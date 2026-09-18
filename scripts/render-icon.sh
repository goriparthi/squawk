#!/bin/bash
# Re-renders every shipped PNG from design/, then builds the .icns.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
out="app/Resources/generated"
swift scripts/render-icon.swift design "$out"
iconutil -c icns "$out/Squawk.iconset" -o "$out/Squawk.icns"
rm -rf "$out/Squawk.iconset"
echo "built $out/Squawk.icns"
