# Island v2 — Design update

Date: 2026-10-31
Builds on: `2026-10-31-island-design.md` (v1, built and reviewed). Everything in v1 still holds unless this document changes it.
Status: Charvit sent a list of changes and said to continue development (no separate approval round). The calls below marked **(my call)** are mine; each is cheap to change.

## 1. What changed in intent

Island will be made **public later**. So v2 must work on a Mac that has never seen this repo or this developer's username, and Island needs an **app icon**. Everything else is the list of changes Charvit sent.

## 2. Changes

**Theme and shape**
- Black and **cyan** replaces black and orange everywhere (buttons, pins, selection, highlights).
- The island gets a more native look: concave "ears" at the top corners that blend into the screen edge, and rounder bottom corners.

**Focus tab (Pomodoro, keep awake)**
- Layout: Pomodoro/stopwatch takes **65%** of the tab width, keep awake the other 35%.
- Top of the Pomodoro column: a **Pomodoro | Stopwatch** switch. Then the time with **− / +** minute buttons (hold to repeat) that change the length of the current phase, then Start/Pause/Reset/Skip.
- Where "Last 7 days" was: a **mascot carousel** (arrows to page, tap to choose) plus a shuffle toggle. The 7-day chart, its data and its recording are removed. The mascot picker leaves Settings, and so do the focus, short-break and long-break minutes.
- While a Pomodoro or stopwatch **runs**, the mascot drifts gently up, down, left and right, both on the open card and in the collapsed pill. It rests when paused or idle. **(my call)** It is drawn at a low frame rate and its CPU cost is measured, because a plain always-on animation cost about 3% of a core.

**Keep awake without the repo**
- The one-time setup moves **inside the app**. The Keep awake card shows what Island needs and an **Allow…** button. It asks for the password through the standard macOS dialog and installs the same narrow rule (only `pmset -a disablesleep 0` and `1`, no password) for the **current user**, in `/etc/sudoers.d/island-<user>`, checked with `visudo` before it goes live. **(my call)** This keeps the exact `stayawake` behavior (works with the lid closed), which v1 chose.
- A Settings row shows whether the permission is installed and can remove it (another password dialog).
- The hard-coded username, `scripts/install-sudoers.sh` and every message that mentions the repo or a script are removed.

**Pin and tab order**
- A **pin** button beside the gear: while pinned the island stays open. **(my call)** The pin is not remembered across launches, so the app never opens permanently by surprise.
- Settings lets the user **reorder the tabs** (up/down buttons per tab). The tab bar and the swipe order follow it, and unknown or missing tabs are handled.

**Clipboard**
- Each record gets a **delete** icon.
- "Clear" becomes **Clear All** and deletes every record. **(my call)** Pinned ones too, but it takes two taps: the first arms it ("Tap again to clear all"), so a stray click cannot wipe pins.
- Image records get a third action, **Scan text**, that copies the text found in the image (running recognition now if it has not run).

**Shelf**
- Dragging files toward the notch **always opens the Shelf tab**, whatever tab was last used, even if the island is already open.
- Tiles are **selectable** (click toggles). An **action bar** appears under the grid for the selection:
  - two or more files: **Zip** them into one archive (`Archive.zip`, numbered if taken, next to the first item);
  - convertible images/PDFs: **Convert to** the other formats (the format they already are is left out);
  - a single zip: **Unzip**; any selection: **AirDrop**, **Remove from shelf**;
  - exactly one file: **Show in Finder**: reveals the file; if it is gone, opens the folder it was in; if that is gone too, opens the home folder **(my call: a stand-in for Finder's "default landing page")**.
- The per-tile ⋯ menu goes away. Dragging a tile out stays copy-only (v1).

**Stats**
- Tapping the **CPU** or **Memory** row opens a list of the **top apps** by that measure (grouped by app, top 5, live while open).
- A **Storage** row always shows available space and total on the home volume.

**Camera**: a **Flip** button toggles the mirror (the current mirrored view stays the default); the choice is remembered.

**Mission Control**: while Mission Control is on screen the island does **not open** (hover, drag or click), and an island that is open closes. The collapsed wings (mascot and time) still show if something is running. Finding from a spike on this Mac: while Mission Control is open there is an on-screen window owned by `WindowManager` at layer 14, full screen width and about 250 points tall (the Spaces bar), and none exist otherwise. The check happens only when the island is about to open, and by a half-second timer while the island is open or pinned. Nothing runs while idle.

**Apps tab removed.** Its code, data file and the "drop an app to pin" rule go.

**Calendar tab (new, last in the default order)**
- Left ~36%: a month grid like the macOS widget (month and year, ‹ › to change month, weekday letters, today in a cyan circle, a dot under days that have events). Clicking a day selects it. **(my call)**
- Right: the selected day's events (today by default): all-day first, then by start time, with time range, title and the calendar's colour. An empty day says so.
- Uses Apple's calendar access (all calendars the user has in macOS). The first visit asks permission; denied shows a message and a button to open Privacy settings.
- **Event alerts**: 10 minutes before a timed event (not all-day), the island **opens a little** (a banner under the notch, not the full island) showing "Starts in 10 min", the event name and the time, for about 10 seconds, then closes. Hovering it keeps it; clicking dismisses it. Each event alerts once. An app started inside the last 10 minutes alerts straight away for an event that has not yet started. No sound and no system notification. The banner does not appear while Mission Control is open (it waits).

**App icon**: black rounded square with a cyan notch pill and a blob-buddy mascot; made by a script, committed as `Packaging/AppIcon.icns`, copied into the app by the build.

## 3. Goals, non-goals, anti-goals

Carried over from v1 and unchanged: never move, overwrite or delete the user's files; no passwords in clipboard history; keep awake only on the user's say-so with the accepted crash gap; idle CPU near zero (timers only while their feature is live or visible); camera off when its tab is not visible; the island never blocks the menu bar beyond the narrow wings.

Added: no feature may depend on this repo or on a particular username; unknown or missing saved settings must never wipe the user's settings (needed because settings gain fields).

Not in this round: notarization and Developer ID signing, auto-update, a website, localisation. `docs/distribution.md` will list the steps for the public release.

## 4. Left to the builder
Exact spacing and animation curves; the icon's exact artwork within the description above; how many mascots show per carousel page (about five); the exact top-corner radii; how the stats dropdown scrolls.
