# Island

**Use your Mac's notch as power.** Island turns the notch (or, on a Mac without one, a small notch of its own) into a
Dynamic-Island-style control centre: a focus timer, your clipboard history, a file shelf, your calendar, GitHub pull
requests, a pocket web browser with an ad blocker, and more. It lives at the top middle of the screen and opens when you point at
it. It has no Dock icon and uses very little memory (about 16 MB when idle).

## Download

1. Get **`Island-1.0.0.dmg`** from the [Releases page](https://github.com/CharvitZalavadiya/Island/releases).
2. Open it and drag **Island** onto **Applications**, then open Island from there.
3. **The first time, macOS will warn you** that it cannot verify the app. That is because Island is not signed with a paid
   Apple developer account (the code is open, read it here). To open it anyway, once:
   - **System Settings → Privacy & Security**, scroll to the message about "Island", press **Open Anyway**; or
   - in Terminal: `xattr -dr com.apple.quarantine /Applications/Island.app`
4. Look at the top middle of your screen and point at it.

To quit, open the island and choose the gear icon → **Quit Island**. It can start at login (Settings).

### Updating

Open Island → gear icon → **Settings → Updates → Check for updates**. If there is a newer version it shows what is new;
**Install and restart** downloads it, replaces Island and opens it again. Nothing to delete, no disk image to open, and your
settings, logins and bookmarks stay. Island also looks about once a day by itself (switch that off in the same place), and the
gear menu says when an update is waiting. Versions before 1.1.0 cannot update themselves: install 1.1.0 once as above.

### Requirements

- macOS **14.2 (Sonoma) or later**.
- **Any Mac.** On a MacBook with a notch the island sits in the notch. On every other screen (older MacBooks, Intel Macs,
  external displays) Island draws a small artificial notch of its own, as tall as the menu bar, in the same place.
- Apple Silicon and Intel are both built. Island is developed and tested on Apple Silicon with macOS 27; the Intel build and
  older macOS versions are built but have not been tried yet, so please report problems.

## Using it

- **Open it** by pointing at the notch or clicking it; it closes when the pointer leaves. The **pin** keeps it open.
- **Switch tabs** with the icons along the top, or swipe sideways. In Settings (right-click the island) you can drag tabs into the order you like, and switch off the ones you do not want; they come back when you switch them on again.
- **Max** (the arrows button) opens it big, on most of the screen; handy for the browser.
- **Focus mode** (the button with the card, next to Max) blurs everything else on the screen and shows the island as a big
  card in the middle of it, 95% of the screen wide and hanging just below the notch. **Esc** or a click anywhere outside the card ends it, and
  the island is as it was before.
- **Keyboard shortcuts.** Click the open island once (that is what gives it the keyboard; hovering never does, so it cannot
  take your typing) and then **F** opens focus mode (and leaves it), **M** switches between the usual size and Max, **P** pins
  or unpins, and **⌘,** opens Settings. The letters only count while you are not typing into a text box or a web page, and the
  keyboard goes back to the app you were in when the island closes.
- While it is closed, small **wings** beside the notch show what is live: the timer, keep-awake, music playing, a Focus mode.

## What is in it

| Tab | What it does |
| --- | --- |
| **Focus** | Pomodoro timer with a mascot (25 to choose from) and background sounds |
| **Awake** | Keep the Mac awake (even with the lid closed), end a program, free a busy port |
| **Clipboard** | History with search, text recognition in images, smart actions |
| **Shelf** | A place to drop files, and your new screenshots |
| **Stats** | CPU, memory, network, storage, a speed test, and a sound mixer (overall and per-app volume) |
| **Camera** | A quick mirror before a call |
| **Calendar** | Your events, with an alert and a Join button a few minutes before |
| **Tasks** | Local tasks, or your Todoist tasks |
| **GitHub** | Open a pull request in any repository (the branch lists open with the 20 most recently pushed branches, newest first, and typing searches GitHub for any other), see yours and the ones waiting for your review, search any repository, review (approve, request changes, comment), and in Max or focus mode read the changed files with their diffs (and filter them by name), as on GitHub's Files changed tab |
| **Teams** | *Experimental.* Your Microsoft Teams chats; needs an app you register in your own Microsoft Entra |
| **Base64 & Cron** | Encode and decode, and explain a cron expression in words |
| **Tools** | Now playing with controls, colour picker, a keyboard lock for cleaning, and trackpad gestures (*experimental: the trackpad is read through a macOS library that is not public*): slide one finger along an edge to change the volume, the screen's brightness or the keyboard light (the top edge starts as the keyboard light), or to skip through what is playing, and tap with three or four fingers, twice or three times, or tap and hold them still for a second, to copy, paste, take a screenshot, open an app, run a Shortcut (which can turn Do Not Disturb on or off), put the app you are in into full screen and back, lock the screen, start the screen saver and more. Both are on from the start; each has its own tile in the tab (*Slide gestures*, *Tap gestures*) that opens its settings in a popup |
| **Browser** | Tabs (down the side or along the top), bookmarks, ad blocking (YouTube included), tabs that sleep to save memory |

## Permissions and privacy

Island asks only when you use a feature, and explains why:

- **Camera** (Camera tab, only while it is showing) · **Calendars** (Calendar tab, read only) ·
  **Audio capture** (per-app volume, only for an app you turn down) · **Accessibility** (the keyboard lock) ·
  **Focus status** (the Focus indicator) · **Desktop folder** (new screenshots on the shelf).
- **Keep awake with the lid closed** needs an administrator password once, to allow one `pmset` command. It is set up
  from Settings and can be removed there.
- Tokens you paste in (GitHub, Todoist) and the Microsoft sign-in are kept **on your Mac**, in Island's own folder
  (`~/Library/Application Support/Island/secrets`), in files only your account can read (permissions 600), left out of
  backups, and deleted when you disconnect. **Island does not use the Keychain**, on purpose: because the app is signed
  without a paid Apple certificate, macOS would ask for your Mac password for each saved token after every update. The
  trade-off is that any program running as you can read those files; use a token with only the permissions Island needs
  (GitHub: `repo`), and disconnect when you are done. Updating Island replaces only the app, never that folder, so you
  make a token once and the same one keeps working after every update (it is only asked for again if the service itself
  revokes it or it expires).
- There is **no analytics and no telemetry**. Island talks only to the services you connect (GitHub, Todoist, Microsoft),
  to the websites you open in its browser, to Apple for the speed test, and to GitHub to ask whether a newer version exists
  (about once a day; nothing about you or your Mac is sent; it can be switched off).
- The browser keeps its own logins, separate from your other browsers, and "Sign out of all sites and clear data" is in its menu.

## Good to know

- The **ad blocker** uses WebKit's content-blocking rules plus a YouTube-specific script. YouTube changes often and fights
  ad blockers, so it will need updating from time to time.
- **Now playing** uses a small helper that talks to a private part of macOS. It can stop working after a macOS update; the
  tile then says "Player unavailable".
- An update **replaces the app and restarts it**. Because the app is signed without a paid Apple certificate, macOS may ask
  again for permissions (camera, calendar) after an update.

## Build from source

You need macOS with Xcode installed (the Swift toolchain and the macOS SDK).

```sh
swift build                 # debug build
swift test                  # the tests
scripts/build-app.sh        # build/Island.app (Apple Silicon only, quick)
scripts/release.sh          # dist/Island-<version>.dmg, universal (Apple Silicon + Intel), with checks
```

How releases are made (build on `dev`; merging a pull request into `main` publishes one when the version in `Sources/IslandCore/Version.swift` is new) and
how signing and notarizing work are in [docs/distribution.md](docs/distribution.md). macOS remembers the permissions you give
Island (calendar, camera, folders) by who signed the app, so `scripts/build-app.sh` signs every build with the same
Apple Development certificate (it remembers which in `build/.signing-identity`) and tells you if another copy of Island, like
one in /Applications, is signed differently: macOS keeps one set of permissions for both, so whichever you open second asks
again. To try how Island looks on
a Mac without a notch, start the built app with `--simulate-no-notch`.

## License

[Apache License 2.0](LICENSE). The GitHub mark in the GitHub tab is from GitHub's
[Octicons](https://github.com/primer/octicons) (MIT).
