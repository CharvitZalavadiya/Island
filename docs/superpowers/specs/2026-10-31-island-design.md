# Island — Design

Date: 2026-10-31
Owner: Charvit
Status: Draft for approval. Nothing has been built yet.

## 1. Intent

Island is a personal macOS app that turns the MacBook notch into a small expandable "Dynamic Island" with a few everyday tools: a Pomodoro timer with mascots, a keep-awake switch, clipboard history, a file shelf, and a handful of utilities.

It is inspired by Notchy (notchy.dev), a paid closed-source app. Island is **not** a copy. It is Charvit's own version of a chosen subset of Notchy's 74 features. All code and art are original. It runs on Charvit's own Mac only and is never distributed.

**Why:** Charvit wants these tools in one place, always one hover away, without paying for or depending on a third-party app. Charvit also already has a `stayawake` zsh function that they want available as a click instead of a terminal command.

**What success looks like:** Charvit installs `Island.app` (or `Island.dmg`) on their own Mac and uses it daily. It sits quietly at the notch, uses almost no CPU while idle, and every feature below works as described.

## 2. Scope

Numbers refer to Notchy's own feature list, which Charvit picked from.

| # | Feature | Where it lives |
|---|---|---|
| 6 | Pomodoro timer (chained sessions, stopwatch mode, 7-day streak chart) with mascots | Focus tab and collapsed pill |
| 7 | Focus mode indicator | Collapsed pill |
| 8 | Keep awake, with a minutes input and a Stop button | Focus tab and collapsed pill |
| 11 | Clipboard history | Clipboard tab |
| 12 | Pinned clips | Clipboard tab |
| 13 | File shelf | Shelf tab |
| 14 | Screenshot shelf | Shelf tab |
| 15 | Image converter | Shelf tab |
| 16 | Zip and unzip | Shelf tab |
| 17 | OCR and searchable clipboard | Clipboard tab |
| 18 | AirDrop from the shelf | Shelf tab |
| 19 | Clipboard smart actions | Clipboard tab |
| 28 | System stats (CPU, memory, network) | Stats tab |
| 53 | Camera mirror | Camera tab |
| 56 | App launcher | Apps tab |
| 58 | Hover and swipe gestures | The island itself |

Also included, because the features above need them: the notch window, expand and collapse, tabs, a settings window, and a way to quit.

## 3. Goals, non-goals, anti-goals

**Goals**
- The 16 features above work as described in section 6.
- Pomodoro has many mascots (about 12 at launch), all in the "blob buddy" style Charvit chose, and adding another is one small file.
- Keep awake behaves exactly like Charvit's `stayawake` function.
- One command builds `Island.app` and `Island.dmg`.

**Non-goals**
- Every other Notchy feature (music, HUDs, AI usage, terminal, widgets, face unlock and so on).
- App Store distribution, notarization, auto-update, localization, Intel Macs, Macs without a notch as a first-class target.
- Cloud sync or accounts.

**Anti-goals (a failure even if the feature technically works)**
- Island leaves the Mac unable to sleep when Charvit did not ask for it. Example: Island is left running, or a timed session ends, and the Mac stays awake. Island must always restore sleep on a timer end, a Stop, and a normal quit.
  - **Accepted gap (Charvit's decision):** if Island crashes or is force-quit while keep awake is on, sleep is restored only the next time Island launches. There is no watchdog process. Charvit chose this to keep the app simple.
- Island loses, moves, overwrites or deletes any of Charvit's files.
- Passwords or other secrets from a password manager end up in clipboard history.
- Island burns CPU or battery while idle, or leaves the camera on when the camera tab is not visible.
- The Island window blocks clicks on menu bar items or apps next to the notch, beyond the narrow wings described in section 6.1, and only while a live activity is showing.

## 4. Constraints and decisions Charvit made

These came from Charvit directly:
- Project name is **Island**. App is `Island.app`, installer is `Island.dmg`.
- Mascot style is the **blob buddy** (a round, ghost-like character whose face changes with the session). Charvit wants **many** mascots.
- Keep awake uses the **exact `stayawake` behavior**: `pmset -a disablesleep 1`, which keeps the Mac awake even with the lid closed.
  - There is an input where Charvit enters a number of minutes. That number is the duration, like the argument to `stayawake`.
  - A **Stop** option is shown whenever keep awake is on.
  - Charvit approved a **sudoers rule** so the app can run exactly two `pmset` commands without a password. See section 6.3.
- Crash protection for keep awake is **next-launch recovery only**. Charvit chose not to add a watchdog process.
- The collapsed pill uses **wings beside the notch**. They appear only while a live activity is showing, are only as wide as their content needs, and nothing extends when idle. (Charvit answered "a" to the pill question, and the first option offered was the wings. I am reading it that way; please confirm.)
- Charvit's `stayawake` function (in `~/.zshrc`) uses: `sudo pmset -a disablesleep 1` to start, `sudo pmset -a disablesleep 0` to stop, no argument means indefinite.

## 5. My calls (Charvit has not agreed to these; please check them)

- Island targets only the macOS Charvit runs now (macOS 27.0.1, Apple Silicon, Xcode 27.1, Swift 6.4). No older macOS support.
- App Sandbox is off. Several features (zip, file shelf, launching apps) need it off.
- Data lives in `~/Library/Application Support/Island`.
- Island shows on the built-in display with the notch. If there is no notch screen (for example the lid is closed and an external monitor is used), it shows a small pill at the top-center of the main display so the app is still usable.
- Island has no Dock icon (`LSUIElement`). Settings and Quit are reachable from a gear button in the expanded island and from right-clicking the pill.
- "Launch at login" is a setting, off by default.
- No system notifications. When a Pomodoro session ends, Island plays a short sound and the mascot does its "done" animation.
- Tabs, in order: Focus, Clipboard, Shelf, Stats, Camera, Apps. The visual layout of the tabs is left to the builder.
- Signing uses Charvit's existing "Apple Development" identity, so macOS permission grants (camera, Focus, folder access) survive rebuilds. Without it, the build falls back to ad-hoc signing and warns that permissions may reset.

## 6. Behavior by feature

### 6.1 The island itself (base, #58)
- A borderless panel at the top-center of the screen, sized from `NSScreen.safeAreaInsets` and the notch's auxiliary areas.
- **Collapsed:** with nothing live, Island draws nothing beyond the notch itself. While something is live (running Pomodoro with mascot and time, keep-awake indicator, Focus indicator, a brief flash for a new screenshot), it shows **wings**: small black extensions to the left and right of the notch, into the menu bar. Each wing is only as wide as its content, with a cap of about 110 points per side (my call), and the wings disappear when the activity ends.
  - The wings receive mouse events (hover opens the island). They cover a small part of the menu bar beside the notch while showing, which Charvit accepted.
  - Outside the wings, the panel is click-through, so the rest of the menu bar and the apps below stay usable.
- **Expanded:** opens when the mouse hovers over the pill. It collapses a moment after the mouse leaves. A two-finger horizontal swipe switches tabs.
- Settings: hover-open on or off (if off, click opens it), and the collapse delay.
- When collapsed, only the pill itself receives mouse events. Everything around it, including menu bar items, stays clickable.

### 6.2 Pomodoro (#6) and mascots
- Sessions: focus, short break, long break. Defaults 25, 5 and 15 minutes, with a long break after every 4 focus sessions. All are editable.
- **Chaining:** when a session ends, the next one can start automatically (a setting).
- **Stopwatch mode:** counts up with no target.
- **Streak chart:** completed focus sessions per day for the last 7 days, stored locally.
- The timer stores an absolute end time, so it stays correct if the Mac sleeps or the app is paused.
- **Mascots:**
  - About 12 at launch, all in the blob buddy style. They differ in color, shape and accessories (ghost, cat-ear blob, cloud, flame, water drop, cactus and so on).
  - Each mascot has three moods: **focus** (determined), **break** (sleepy), **done** (celebrates).
  - Charvit picks a mascot in settings. There is also a **shuffle** option that picks a different mascot each session.
  - The mascot sits on the collapsed pill next to the countdown while a session runs.
  - Mascots are drawn in code (SwiftUI shapes), with no image files. Each mascot is a single Swift file, and one registry lists them, so adding another means adding one file.
  - The look must stay close to the blob buddy mockup, option A in `docs/superpowers/specs/assets/mascot-styles-mockup.html` (open it in a browser; the other options B to D in that file were not chosen).
  - The reference shape is a 26x26 white body: a rounded dome on top (`M4 22V12a9 9 0 0 1 18 0v10l-3-2-3 2-3-2-3 2-3-2z`) with a wavy ghost-like bottom edge, two dot eyes (radius 1.6 at x=10 and x=16, y=12), and short brow strokes for the focus mood. It bobs up and down gently. The other mascots vary this silhouette, color and accessories while keeping the same simple, rounded, two-dot-eye look.

### 6.3 Focus indicator (#7) and keep awake (#8)

**Focus indicator.** When a macOS Focus mode (Do Not Disturb or similar) is on, the pill shows a small indicator. Use Apple's public Focus status API (`INFocusStatusCenter`), which asks for permission once. It can only say whether a Focus is on, not which one. If permission is denied, the indicator is simply hidden.

**Keep awake.**
- UI in the Focus tab: a number field for **minutes** and a **Start** button. An empty field means indefinite, like running `stayawake` with no argument.
- While it is on, the Focus tab shows the time remaining (or "indefinite") and a **Stop** button. The collapsed pill shows a small indicator.
- Start runs `sudo -n /usr/bin/pmset -a disablesleep 1`. Stop, and the timer ending, run `sudo -n /usr/bin/pmset -a disablesleep 0`.
- The deadline is an absolute time, so a timed session ends on time even after sleep or wake.
- **Sudoers rule.** Charvit installs this once, themself. I will provide `scripts/install-sudoers.sh`, but I will not run it. The script writes `/etc/sudoers.d/island` with mode 0440 after checking it with `visudo -cf`, and the rule is:
  `charvit ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1`
  If the rule is not installed, Island shows a clear message with the command to run, and Start does nothing.
- **Safety net (my call, refined from what I said in chat):**
  - Island remembers in a small state file when it turned keep awake on.
  - When Island quits normally, it turns keep awake off **only if Island started the session** (my call). A session started from the terminal with `stayawake` is left alone.
  - If the system reports `SleepDisabled` on but Island did not start it, the Focus tab shows "On (started outside Island)" with a Stop button (my call). Pressing Stop is an explicit action by Charvit, so it is allowed to end that session.
  - If Island starts and its state file says it left keep awake on (a crash), it turns it off, because the previous run did not stop it.
  - Island does **not** blindly reset `disablesleep` on every launch. That would break a `stayawake` session running in a terminal.
- **No watchdog (Charvit's decision).** If Island dies while keep awake is on, the Mac stays unable to sleep until Island is launched again, or until Charvit runs `sudo pmset -a disablesleep 0` in a terminal. The Focus tab's keep-awake help text shows that command. Turning on "launch at login" makes the next-launch recovery happen sooner after a reboot.
- The status shown in the UI is read from `pmset -g` (the `SleepDisabled` value), so it stays truthful if something else changes it. The terminal `stayawake` function and Island write the same system setting, so whichever acts last wins.
- No low-battery guard in the first version, to match `stayawake` exactly.

### 6.4 Clipboard (#11, #12, #17, #19)
- Watches the pasteboard for text, links, images and files. The history keeps the latest 200 items. Items persist across restarts.
- Items the system marks as concealed, transient or auto-generated (the convention password managers use) are **never recorded**.
- **Pinned clips** survive "Clear history".
- Clicking an item puts it back on the clipboard. It does not paste automatically.
- **Smart actions:** a link offers Open and Copy. A hex color shows a swatch and offers copy as RGB. An email address offers Compose and Copy.
- **OCR:** when an image is copied, on-device text recognition (Apple Vision) extracts its text. The search box searches both copied text and recognized image text. Nothing leaves the Mac.

### 6.5 Shelf (#13, #14, #15, #16, #18)
- **File shelf:** drag files or folders onto the island to add them, and drag them out to use them. Items persist across restarts. The shelf holds references to the files. It never moves or deletes the originals. If an original disappears, its item is greyed out and can be removed.
- **Screenshot shelf:** Island watches the system screenshot folder (currently the default, the Desktop). New screenshots appear on the shelf as draggable thumbnails, and the pill flashes briefly.
- **Image converter:** drop images onto a convert target and choose HEIC, PNG, JPEG, TIFF or PDF. It runs offline. The result is written next to the original with the new extension, and never overwrites an existing file (it adds a number instead).
- **Zip and unzip:** a selected shelf item can be zipped, and a zip can be unzipped. The result goes next to the original, and never overwrites.
- **AirDrop:** send selected items with the system AirDrop sharing service.

### 6.6 Other tabs
- **Stats (#28):** CPU %, memory used, and network up and down. Updates about every second while the island is expanded, and stops (or drops to a very slow rate) while it is collapsed.
- **Camera (#53):** a live, horizontally mirrored preview for checking yourself before a call. The camera runs only while this tab is visible, and stops when the tab changes or the island collapses.
- **Apps (#56):** a grid of pinned apps. Add by dragging an app in or using a picker. Drag to reorder. Click to launch. The layout persists.

## 7. Permissions Island will ask for
Camera (camera tab), Focus status (Focus indicator), and access to the Desktop folder (screenshot watching). Island does **not** need Accessibility, Screen Recording, Input Monitoring or Full Disk Access for the selected features.

## 8. Packaging
- One script builds a Release `Island.app` from the command line, signs it, and produces `Island.dmg`. The DMG can use `create-dmg` (not installed; `brew install create-dmg`) or the built-in `hdiutil`.
- Charvit can also copy `Island.app` straight into `/Applications`. The DMG is only packaging.
- No Apple Developer Program, notarization or Gatekeeper workarounds are needed on Charvit's own Mac, because the app is built there and never downloaded.

## 9. Testing
- Automated tests for the logic that can be tested without a screen: the Pomodoro state machine, the keep-awake controller (with a fake command runner, never running real `pmset` in tests), clipboard filtering of secrets, image conversion, and zip/unzip.
- A short manual checklist for the visual and permission-based parts (notch panel, hover, camera, AirDrop, Focus).

## 10. Left to the builder
- Project structure (Xcode project or Swift package plus a bundling script), as long as the single build command in section 8 works.
- Exact visual design, spacing and animations of the tabs, within the blob buddy look.
- The exact list of the 12 mascots.
- How the collapsed pill arranges several live activities at once.
- How the Focus indicator degrades if the API behaves differently than documented.
- Storage format for history, shelf and settings.
