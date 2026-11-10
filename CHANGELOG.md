# Changelog

## Unreleased

- **Choose your tabs.** In Settings, each tab now has a switch: switch off the ones you do not use and they leave the island,
  switch them on again whenever you like (all are on to start with, and at least one stays on). The up and down buttons are
  gone: grab a row by its handle and drag it where you want it. A file dragged toward the notch only opens the island while
  the Shelf tab is on, and a pull request link in Teams opens in your browser while the GitHub tab is off.
- **A new app icon.** A light glass square with the open island hanging from the top: six tiles for Tasks, GitHub, Teams,
  Calendar, Player and Browser, and a progress bar. It replaces the dark square with the ghost.
- **No more Keychain password prompts.** Opening the Tasks, GitHub or Teams tab could make macOS ask for your Mac password
  (and would have after every update). Island now keeps its tokens in files only your account can read, in its own data
  folder, and never touches the Keychain. *You will need to connect GitHub, Todoist and Teams once more.* The README says what
  this trades away.

## 1.1.0

- **Updates from inside Island.** Settings has an *Updates* section: *Check for updates* looks on GitHub, shows what is new,
  and *Install and restart* downloads the new version, checks it, replaces the app and opens it again. No more deleting the
  app and downloading the disk image by hand. Island also looks about once a day by itself (it can be switched off), and the
  gear menu says when one is waiting.
- The version now comes from one place (`Sources/IslandCore/Version.swift`), and a new release is built and published
  automatically when changes are merged into `main`.

## 1.0.0

The first public release.

- A notch-based island with 13 tabs: Focus, Awake, Clipboard, Shelf, Stats, Camera, Calendar, Tasks, GitHub, Teams
  (experimental), Base64 & Cron, Tools and Browser.
- A browser in the island: tabs down the side or along the top, bookmarks, ad blocking including YouTube, tabs that go to
  sleep to save memory, and **Max** mode (the island on most of the screen).
- GitHub: open pull requests, see your own and the ones waiting for your review, search any repository, and review (approve,
  request changes, comment) right from the island.
- An **artificial notch** on Macs and screens that have none, so Island works on every Mac, not only those with a notch.
- Runs on macOS 14.2 or later; built for Apple Silicon and Intel.
