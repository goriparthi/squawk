#!/bin/bash
# Builds a distributable DMG, notarized and stapled when credentials exist.
#
# Notarization needs a Developer ID Application certificate plus a notarytool
# keychain profile. Create one with:
#   xcrun notarytool store-credentials squawk-notary \
#     --key <AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
cd "$REPO_ROOT"

"$REPO_ROOT/scripts/bundle.sh"

VERSION="$(version_from_plist)"
DMG="dist/${APP_NAME}-${VERSION}.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "dist/${APP_NAME}.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"

IDENTITY="$(find_signing_identity)"
if [[ -z "$IDENTITY" ]]; then
    echo "no Developer ID identity; $DMG is unsigned and cannot be notarized"
    exit 0
fi
codesign --force --sign "$IDENTITY" "$DMG"

if ! PROFILE="$(find_notary_profile)"; then
    echo "built $DMG (signed, NOT notarized: no notarytool profile found)"
    exit 0
fi

echo "notarizing with profile: $PROFILE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "built $DMG (signed, notarized, stapled)"
