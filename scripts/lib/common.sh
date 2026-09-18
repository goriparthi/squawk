# Shared shell helpers. Sourced, never run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

APP_NAME="Squawk"
BUNDLE_ID="com.goriparthi.squawk"
export APP_NAME BUNDLE_ID

version_from_plist() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$REPO_ROOT/app/Resources/Info.plist"
}

find_signing_identity() {
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        echo "$CODESIGN_IDENTITY"
        return
    fi
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' \
        || true
}

# Notary profiles are per Apple ID, not per app, so an existing profile for
# another of this account's apps is the same credential and is accepted.
find_notary_profile() {
    local candidate
    for candidate in "${NOTARY_PROFILE:-}" squawk-notary hangar-notary; do
        [[ -z "$candidate" ]] && continue
        if xcrun notarytool history --keychain-profile "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}
