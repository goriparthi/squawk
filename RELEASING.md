# Releasing

1. Bump `CFBundleShortVersionString` in `app/Resources/Info.plist`.
2. `make test` and `make smoke` must both be green.
3. `make dmg` builds, signs, notarizes and staples `dist/Squawk-<version>.dmg`.
4. Tag and publish:

```sh
git tag -a v<version> -m "Squawk <version>"
git push origin v<version>
gh release create v<version> dist/Squawk-<version>.dmg --title "Squawk <version>" --notes-file <notes>
```

## Notarization

Needs a Developer ID Application certificate and a notarytool keychain profile:

```sh
xcrun notarytool store-credentials squawk-notary \
  --key <AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
```

The `.p8` is a private key. Once stored in the keychain the file is no longer
needed; keep it somewhere safe or delete it, and never commit it.

`scripts/package-dmg.sh` looks for `$NOTARY_PROFILE`, then `squawk-notary`, then
any other profile on the same Apple ID. Without one it still builds and signs,
and says plainly that the DMG is not notarized.

## Checks before publishing

```sh
spctl --assess --type execute --verbose=2 dist/Squawk.app   # expect: accepted
xcrun stapler validate dist/Squawk-<version>.dmg
```
