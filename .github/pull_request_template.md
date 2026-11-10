## What changes

<!-- A sentence or two: what is different for someone using Island? -->

## Releasing

Merging into `main` publishes a release automatically **if the version is new**.

- [ ] This does not need a release (the version in `Sources/IslandCore/Version.swift` is unchanged), **or**
- [ ] I raised the version in `Sources/IslandCore/Version.swift` and added a `## <version>` section to `CHANGELOG.md` saying what changed.

## Checked

- [ ] `swift test` passes
- [ ] I tried it in the app (`scripts/build-app.sh && open build/Island.app`) where it matters
