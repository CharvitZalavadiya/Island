# Making and publishing a release

## The rule

**A release is published when a change lands on `main` and the version in `Sources/IslandCore/Version.swift` is one that has
not been released yet. Otherwise nothing is published.**

So you can merge into `main` as many times as you like without releasing. When you want a release:

1. Raise the version in `Sources/IslandCore/Version.swift` (`public let islandVersion = "1.2.0"`). That is the only place the
   version lives: the built app is stamped from it.
2. Add a `## 1.2.0` section to `CHANGELOG.md` saying what changed (it becomes the release notes).
3. Merge that into `main`.

The *Release* workflow (`.github/workflows/release.yml`) then builds **whatever is on `main` at that moment**, tags it
`v1.2.0`, and publishes the release with the disk image, its checksum, your changelog section and the install guide.
Merging again without changing the version publishes nothing (the tests still run), because `v1.2.0` already exists.

What the workflow does, in order, on every push to `main`:

| Step | |
| --- | --- |
| Read the version | from `Sources/IslandCore/Version.swift`; must look like `1.2.3` |
| Is it new? | `.github/scripts/release-decision.sh` compares it with the published releases and tags. Already released: stop here (green, nothing published). **Lower than one already released: fail** (the "latest" release must never go backwards). |
| Test | `swift test` |
| Release notes | `.github/scripts/release-notes.sh` takes the `## <version>` section of `CHANGELOG.md` and appends the install guide. **Fails if the section is missing**, so nothing is published without notes. |
| Build | `scripts/release.sh`: a universal app (Apple Silicon and Intel), the disk image `Island-<version>.dmg`, its `.sha256` |
| Publish | a **draft** release is created with both files and published only when the uploads are done, so a failed run leaves nothing half-made |

If a run fails after the version was raised, the next push to `main` tries again (the version is still not released).

A pull request into `main` (or `dev`) runs the *CI* workflow (build and test). If the pull request raises the version it also
checks that `CHANGELOG.md` has notes for it, so a missing entry shows up before merging, not after.

### Branches

Work on `dev`, open a pull request into `main`, merge when the checks pass. In the repository settings it is worth turning on
branch protection for `main` (require a pull request and the *CI* check).

### Doing it by hand

`scripts/release.sh` does the build step on your own Mac and puts the files in `dist/` (it does not publish anything):

```sh
scripts/release.sh
gh release create v1.2.0 dist/Island-1.2.0.dmg dist/Island-1.2.0.dmg.sha256 --title "Island 1.2.0" --notes-file <(.github/scripts/release-notes.sh 1.2.0)
```

## How Island updates itself

Settings → Updates asks `https://api.github.com/repos/CharvitZalavadiya/Island/releases/latest` (the newest published release,
never a draft). If its version is higher than the running one, *Install and restart*:

1. downloads `Island-<version>.dmg` (only from GitHub, over https) and checks it against the release's `.sha256` file; a release
   without one is refused;
2. opens the disk image, copies the app next to the installed one, and checks that it is Island (same bundle identifier), is the
   version the release says and newer than this one, has code for this kind of Mac, and has an intact signature;
3. quits Island; a small script waits for it to exit, moves the old app aside, moves the new one in (and puts the old one back if
   that fails), and opens it again.

So **do not rename the release files**: the updater looks for `Island-<version>.dmg` and `Island-<version>.dmg.sha256`.

It needs to be able to write where Island is installed (normally `/Applications`); if not, or if Island is running from a
disk image or from Downloads, it says so and links to the release page.

*Trust:* an update is as trustworthy as the GitHub repository's releases and the checksum published next to the file, which
protects against a corrupted or swapped download but not against someone who controls the repository. Signing with a Developer
ID certificate (below) and verifying that signature would be the next step.

## Signing: what people see when they open the app

| Signed with | What macOS does on someone else's Mac |
| --- | --- |
| **Nothing paid (ad-hoc), what the workflow does** | Works, but the first launch is blocked with "cannot verify". The person presses *Open Anyway* in System Settings → Privacy & Security once (or runs `xattr -dr com.apple.quarantine /Applications/Island.app`). The release notes and the disk image's *READ ME FIRST* explain it. **Updates made from inside Island do not show the warning again** (Island downloads them itself, so macOS does not quarantine them). |
| **Developer ID + notarized** | Opens with no warning. Needs the Apple Developer Program (a paid membership). |

An ad-hoc signature also means macOS asks for Camera, Calendar and the other permissions again after each update, because the
signature changes with every build. A Developer ID signature keeps them.

**The same thing is why Island keeps its tokens in files, not the Keychain.** The Keychain only lets an app use an item without
asking while the app has the same signature as the one that saved it; with an ad-hoc signature that is no longer true after
every update, and macOS asks for the person's Mac password once per token. `FileTokenStore` (files with permissions 600 in a
folder with permissions 700 under Island's data folder) asks nothing. Once releases are signed with a Developer ID certificate,
`KeychainTokenStore` (kept in the code, unused) can be switched back on in `IslandServices`; a test fails if anything uses it
before then.

### Getting the warning-free kind

1. Join the Apple Developer Program and create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates).
2. Save notarization credentials once (an app-specific password from appleid.apple.com):
   `xcrun notarytool store-credentials island-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID`
3. `ISLAND_NOTARY_PROFILE=island-notary scripts/release.sh`

With a Developer ID certificate in the keychain the script signs with it using the hardened runtime and
`Packaging/Island.entitlements`, and with `ISLAND_NOTARY_PROFILE` it also notarizes and staples the disk image. To do it in the
workflow, the certificate (as a base64 secret) and the notarization credentials would be added as repository secrets and imported
in a step before the build.
*This path has not been run yet (it needs the paid certificate). If notarization is rejected, the report it prints says what to
add to the entitlements file.*

## What is and is not tested

Built and tested on Apple Silicon, macOS 27. The Intel half of the app and macOS 14.2 to 26 are built (the compiler checks the
APIs against the 14.2 minimum) but have not been run: no Intel Mac or older macOS was available. The release workflow itself
can only be exercised by GitHub: its scripts and the updater are tested here, the workflow's own steps run for the first time on
GitHub.
