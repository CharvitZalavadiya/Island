# Island v3: Charvit's second list of suggestions (2026-11-01)

Charvit's own words are condensed, nothing dropped. "Built" says what exists after v2 so it is clear what changes.
Each item gets a number so tasks and the ledger can refer to it.

## The three phases (also in memory)

1. **Minimal / resting view**: wings beside the notch while he works elsewhere.
2. **Full view**: the expanded island.
3. **Quick view**: a state between the two. Not built, planned for later. Keep the mode logic open to a third state.

## Requests

### Shell and wings
- **S1** Opening the island should animate as smoothly as it already does when closing back to the notch.
- **S2** No camera icon in the minimal view.
- **S3** Keep awake in the minimal view: a cup icon where the mascot sits for Pomodoro, with a round border that shrinks with the time; on the right the time as minutes:seconds. If keep awake is infinite: no border around the cup and an infinity icon instead of the time.

### Colours
- **C1** Stop using cyan for everything. Use several attractive colours (cyan, purple, yellow, orange, white, green…), a different one per thing, not one accent. (Built: a single cyan accent, `IslandTheme.accent`.)
- **C2** Storage bar: the fuller it gets, the redder it turns; the change must be a smooth gradient, not steps. (His wording for the low end is "orangish"; see open question 3.)

### Pomodoro / Stopwatch tab
- **P1** More breathing room between the elements; it is too tight.
- **P2** Remove the Skip button. (Built in v2.)
- **P3** Top rectangle in two equal halves: left = the mascot inside a circular profile-style border in the mascot's own colour, and the border slowly runs out as the timer ends; right = a grid of mascots, vertically scrollable, to pick one. The first block of the grid is Shuffle. Each block has a secondary background colour. (Built: a paged carousel under the timer.)
- **P4** Below it a second rectangle: left = the minutes with the − / + buttons; right = a vertical stack of Start / Pause / Resume and Reset.

### Keep awake (right side of the Focus tab)
- **K1** A scroll wheel for the minutes, 1 to 60, instead of a text field. (Built: a text field.)
- **K2** A round ring around the number that behaves like the Pomodoro ring (shrinks while running).
- **K3** Start button below it. Below that a checkbox "Awake infinitely" (wording his): when ticked, the wheel is disabled and only Start remains.
- **K4** Below that, the current "Stuck awake?" suggestion.
- **K5** The whole panel must be static: nothing may move or resize when buttons are pressed or text changes.

### Clipboard
- **B1** No tooltip on hover ("Click to copy back to clipboard").
- **B2** Pin, Delete and Scan-text buttons are not always visible; they appear on hover. Delete red, Pin yellowish. Scan text should be fast, and be just the copy-text icon (colour as now).
- **B3** Each row has two parts. Left: a square with rounded corners holding the image (cover-fit), or a text icon, or a link icon. Right: the content.
- **B4** For links, like the scan icon for images, show a "redirect / open" icon in its own colour.

### Shelf
- **H1** Tiles a bit more rounded; the rest stays.

### Stats
- **T1** CPU dropdown shows each app's share of the whole, like memory does: if 32 % is in use, "12 % x app, 5 % y app". (Built: percent of one core.)
- **T2** CPU and Memory can both be open at once. (Built: one at a time.)
- **T3** Next to download/upload show other readings if possible, such as CPU temperature.
- **T4** A button that runs a speed test with `networkQuality`.
- **T5** Different colours per reading.

### Camera
- **M1** Remove the Flip button. The picture must behave like a mirror: head moves right, the picture moves right. (His report: it currently moves the other way.) (Built in v2: a Flip button and a saved setting.)

### Calendar
- **L1** Ask for calendar access and show the current month, Sunday to Saturday; Sunday and Saturday in red (holidays); today in another colour inside a circle. (Overlaps the v2 Calendar tab, Task 13.)

## How these meet what is already built

| Item | Effect on existing work |
|---|---|
| M1 | Reverts the Flip button and `isMirrored`/`flip()` (v2 Task 10). Likely cause of the wrong direction: on macOS the preview layer may already mirror the built-in camera by itself, so v1's extra flip cancels it. Fix: set the capture connection's mirroring explicitly instead of a layer transform. Needs his eyes (camera light). |
| T1 | The CPU figure becomes app% ÷ number of cores (share of the whole Mac), with the total shown above. |
| T2 | `StatsSampler.expanded: Metric?` becomes a set; the `ps` loop runs while either is open. |
| P2/P3 | `PomodoroController.skip` stays as logic but loses its button. The carousel is replaced by a grid with a shuffle tile. |
| C1 | `IslandTheme` gets a palette; each tab and wing picks its own colour. |
| K1–K5 | `KeepAwakeCard` and `KeepAwakeViewModel` get a fixed-size layout; the minutes become a 1…60 wheel (the stored default stays). |
| S3 | A keep-awake wing joins the wing layout (currently an icon only). |
| L1 | Folded into Task 13 (the calendar tab), with the weekend and today styling. |

## Decisions (Charvit, 2026-11-01)

1. **CPU temperature (T3): skipped for now.** Next to download/upload only the speed-test button (T4) is added.
2. **Order of work: finish v2 first** (Calendar core and tab, event alerts, app icon, docs), folding the calendar styling (L1) into the Calendar tab; then the rest of this list.
3. **Storage colours (C2): green when mostly empty, through orange, to red when nearly full**, as one smooth gradient.

## Not in this list, still pending from v2

Task 11 live recovery check, Task 12 and 13 (Calendar), Task 14 (event alerts), Task 15 (app icon), Task 16 (docs, packaging, final review).
