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
    # Loudly, and with a failing exit code. This used to print a line and exit
    # zero, so a transient failure reaching Apple produced a DMG that looked
    # built, got released, and would have been refused on the far side.
    echo "no notarytool profile: $DMG is signed but NOT notarized and must not be released" >&2
    echo "set one up with: xcrun notarytool store-credentials squawk-notary \\" >&2
    echo "  --key <AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>" >&2
    echo "to build one deliberately anyway, re-run with ALLOW_UNNOTARIZED=1" >&2
    [[ "${ALLOW_UNNOTARIZED:-}" == "1" ]] && exit 0
    exit 1
fi

echo "notarizing with profile: $PROFILE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "built $DMG (signed, notarized, stapled)"
