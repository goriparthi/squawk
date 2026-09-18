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
# Finding a profile needs a call to Apple, so a network blip looks exactly like
# a missing credential. It is not: one means "ask the user to set this up", the
# other means "wait a moment". Retried, because the difference between them was
# a release that went out unnotarized and would have been blocked by Gatekeeper.
find_notary_profile() {
    local candidate attempt
    for candidate in "${NOTARY_PROFILE:-}" squawk-notary hangar-notary; do
        [[ -z "$candidate" ]] && continue
        for attempt in 1 2 3; do
            local output
            if output="$(xcrun notarytool history --keychain-profile "$candidate" 2>&1)"; then
                echo "$candidate"
                return 0
            fi
            # A profile that genuinely is not there says so, and no amount of
            # waiting will change it. Anything else is worth another try.
            if [[ "$output" == *"No Keychain password item found"* ]]; then
                break
            fi
            sleep $((attempt * 2))
        done
    done
    return 1
}
