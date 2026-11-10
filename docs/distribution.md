# Making and publishing a release

## One command

```sh
scripts/release.sh
```

It checks that the version in `Sources/IslandCore/Version.swift` and `Packaging/Info.plist` agree, builds a **universal**
app (Apple Silicon and Intel), signs it, puts it in `dist/Island-<version>.dmg` with a checksum, and prints what it found:
the architectures, the minimum macOS, whether the signature is valid, and what Gatekeeper says.

To release a new version: change the version in both files, add a section to `CHANGELOG.md`, run the script, then publish:

```sh
git tag v1.0.0 && git push origin main v1.0.0
gh release create v1.0.0 dist/Island-1.0.0.dmg dist/Island-1.0.0.dmg.sha256 --title "Island 1.0.0" --notes-file CHANGELOG.md
```

(`gh` must be signed in to the account that owns the repository: `gh auth status`.)

## Signing: what people see when they open the app

| Signed with | What macOS does on someone else's Mac |
| --- | --- |
| **Nothing paid (ad-hoc), what `release.sh` does without a Developer ID** | Works, but the first launch is blocked with "cannot verify". The person presses *Open Anyway* in System Settings → Privacy & Security once (or runs `xattr -dr com.apple.quarantine /Applications/Island.app`). The disk image's *READ ME FIRST* explains it. |
| **Developer ID + notarized** | Opens with no warning. Needs the Apple Developer Program (a paid membership). |

An ad-hoc signature also means macOS asks for Camera, Calendar and the other permissions again after each update, because the
signature changes with every build. A Developer ID signature keeps them.

### Getting the warning-free kind

1. Join the Apple Developer Program and create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates).
2. Save notarization credentials once (an app-specific password from appleid.apple.com):
   `xcrun notarytool store-credentials island-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID`
3. `ISLAND_NOTARY_PROFILE=island-notary scripts/release.sh`

With a Developer ID certificate in the keychain the script signs with it using the hardened runtime and
`Packaging/Island.entitlements`, and with `ISLAND_NOTARY_PROFILE` it also notarizes and staples the disk image.
*This path has not been run yet (it needs the paid certificate). If notarization is rejected, the report it prints says what
to add to the entitlements file.*

## What is and is not tested

Built and tested on Apple Silicon, macOS 27. The Intel half of the app and macOS 14.2 to 26 are built (the compiler checks the
APIs against the 14.2 minimum) but have not been run: no Intel Mac or older macOS was available. Before a wide release, try the
disk image on one of each if you can.
