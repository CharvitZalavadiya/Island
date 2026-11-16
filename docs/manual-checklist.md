# Island: hands-on checklist

The automated tests cover the logic. These are the things only a person at the Mac can check: the notch window, hover and
swipe, permission prompts, the camera light, dragging files, and the keep-awake safety net. Numbers like #6 are Notchy's
feature numbers that you picked.

## Before you start

- [ ] Build and open it: `scripts/build-app.sh && open build/Island.app` (nothing shows until you hover the notch).
- [ ] For keep awake (#8) install the sudoers rule once, yourself: `scripts/install-sudoers.sh` (preview it first with `scripts/install-sudoers.sh --print`).
- [ ] To check the Pomodoro timer quickly, open it with minutes treated as seconds: `open build/Island.app --args --fast-pomodoro`.
- [ ] To see every wing at once: `open build/Island.app --args --debug-wings`.
- [ ] macOS will ask for these when you first use them: Focus status, access to the Desktop folder, and the camera. Say yes to all three.

## The island itself (#58)

- [ ] Nothing is visible while it is collapsed and nothing is running.
- [ ] Hovering the notch opens the island; moving away closes it after about 0.4 s.
- [ ] A two-finger swipe left and right changes tabs.
- [ ] While collapsed, the menu bar items beside the notch still respond to clicks.
- [ ] The gear menu and right-click both offer Settings… and Quit Island, and Quit works.
- [ ] Changing the display arrangement in System Settings moves the island to the right place.
- [ ] Only one copy runs: with Island open, `open -n build/Island.app` (or opening a second copy from another folder) leaves a single Island, and a running keep-awake session is not ended by the second launch.

## Pomodoro (#6)

- [ ] Start in the Focus tab: the countdown runs and the mascot and time show beside the notch while the island is closed.
- [ ] At the end a sound plays and the mascot celebrates for about 5 seconds.
- [ ] With "start the next session automatically" on, the break starts by itself; with it off, it waits for Start.
- [ ] Pause, Resume, Reset and Skip behave. Stopwatch mode counts up.
- [ ] Today's bar in the 7-day chart grows after a finished focus session.
- [ ] A different mascot in Settings shows straight away; with Shuffle on, each session gets a different one.

## Focus indicator (#7)

- [ ] Turn on a Focus mode (for example Do Not Disturb): a small moon appears beside the notch within a few seconds.

## Keep awake (#8)

Read what the Mac is doing at any time with `pmset -g | grep SleepDisabled` (1 = kept awake, 0 = normal).

- [ ] Type 1 in the minutes box and press Start: it shows 1, and returns to 0 after a minute.
- [ ] Start, then Stop: it returns to 0 straight away.
- [ ] Leave the box empty, Start, then quit Island: it returns to 0.
- [ ] Leave the box empty, Start, then `kill -9` Island: it stays at 1. Open Island again: it returns to 0 (the accepted gap).
- [ ] Type `abc`: a message appears and nothing changes.
- [ ] If `stayawake` in a terminal has it on, Island shows "On (started outside Island)" and Stop turns it off.
- [ ] You can type in the minutes box.
- [ ] If it will not start, the message tells you to run `scripts/install-sudoers.sh`.

## Clipboard (#11, #12, #17, #19)

- [ ] Copy some text, a link, `#FF8800` and an email address: each shows up, with Open, Copy RGB and Email buttons.
- [ ] Copy a screenshot (⌃⌘⇧4) and search for a word that is in it. The first one can take a while to become searchable.
- [ ] Copy a password from a password manager: it must not appear.
- [ ] Pin an item, press Clear: the pin stays, the rest goes.
- [ ] Click an item: the clipboard changes, nothing is pasted, and the list does not reorder.
- [ ] You can type in the search box.

## Shelf (#13, #14, #15, #16, #18)

- [ ] Drag two files toward the notch: the island opens on Shelf and they appear. They are still there after restarting Island.
- [ ] Drag one out into a folder: it is copied, and the original is untouched.
- [ ] Take a screenshot (⌘⇧4): it appears on the shelf with a badge, and the pill flashes. macOS asks about the Desktop folder the first time.
- [ ] ⋯ ▸ Convert to JPEG on a PNG: a new file appears beside it and the original is intact. Converting to the same format makes "name 2".
- [ ] Zip then Unzip a folder: the results are numbered and nothing is overwritten.
- [ ] AirDrop… opens the system picker.
- [ ] Move an original away: the item still finds it. Delete one: its tile turns grey.

## Stats (#28)

- [ ] CPU, memory and network readings move; a big download shows in Download.
- [ ] After collapsing the island there are no periodic wakeups (`sample Island 1`).

## Camera (#53)

- [ ] The first visit asks for permission, then shows a mirrored live picture.
- [ ] The green camera light goes off when you change tab and when the island closes.
- [ ] With the permission off in System Settings, the tab shows a message and a button, with no crash and no light.

## Apps (#56)

- [ ] Add app… (it starts in /Applications) pins apps; dropping an .app on the open Apps tab pins it.
- [ ] Clicking opens the app. Dragging one tile onto another reorders them, and the order survives a restart.
- [ ] Right-click: Show in Finder and Unpin.
- [ ] Move an app out of its folder: its tile dims and clicking explains.

## Focus mode

- [ ] Open the island and click the **card button** (next to Max). Everything else on the screen blurs and dims, and the island becomes a big black card in the middle of the screen (95% of the width, as tall as fits below the notch), with a visible gap of blurred background between the notch and the top of the card: they must not run together. On a display without a notch the card sits just below the menu bar. The tabs work in it as usual (try the Tools and Browser tabs, and typing in a text box).
- [ ] Press **Esc**: the blur goes, and the island is back as it was (if you had it open it is open, then closes by itself when the pointer is away; if it was pinned or Max it still is). The app you were working in has the keyboard again: type a letter and it lands there.
- [ ] Do it again and click on the blur outside the card (top, bottom, a corner): same result, and the click does not reach the app underneath (nothing there is clicked or selected).
- [ ] Press **⌘Tab** to another app while it is on: focus mode ends and that app keeps the keyboard.
- [ ] Try it while an app is in full screen (its own space): the blur and the card appear over it, and Esc brings you back to it. Try it with a second display plugged in: only the island's own display is blurred.
- [ ] In focus mode, Tools ▸ Tap gestures ▸ choose an app: the file chooser opens in front of the card. In the Browser tab a page's alert (any site that shows one) also appears in front. The gear menu ▸ Settings… ends focus mode and opens Settings.
- [ ] Max and Pin are not shown in focus mode; the card button is highlighted, and clicking it leaves too. Esc inside a text box leaves focus mode as well (that is on purpose).

## GitHub: changed files and branches

- [ ] In the GitHub tab open a pull request for review (My PRs or Reviews, or a link pasted into Search) at the usual island size: the review looks as before, with one extra line saying to open Max or focus mode to read the changed files.
- [ ] Switch to **Max** (arrows button) with the review still open: the review moves into a narrow column on the left and the changed files appear beside it: a file list (letters A, M, D, R for added, modified, deleted, renamed, with +/− counts) and every file's changes under each other. Compare one file with the same pull request's *Files changed* tab on github.com: the same lines, the same added and removed ones, the same line numbers.
- [ ] Open a pull request with several files and check that EVERY file shows its changes under its name bar (an empty box under a name bar is a bug, not a short file).
- [ ] Click the *Filter files by name* box above the list (it does not take the keyboard until you click it) and type part of a file's name or folder: only the matching files stay, in the list and below it, and the top line says "showing N". Capitals do not matter; two words must both match; a renamed file is found by its old name too. Type something no file has: it says so and offers *Show all files*. Clear the box (or press its cross): every file is back. The island's letter shortcuts (F, M, P) do not fire while you type there.
- [ ] Click a file in the list: the changes scroll to it. Click a file's name bar: it folds. *Fold all* and *Unfold all* work. The name bar stays at the top while that file's lines scroll under it. Long lines wrap; you can select and copy text from the diff.
- [ ] Open a pull request that renames a file, one with an image or other binary file, and (if you can find one) one with a very large generated file: each says what it is (renamed, or that GitHub does not send the changes) instead of showing an empty box. A pull request with more than a hundred files lists them all.
- [ ] Try **focus mode** (card button) on the same review: the same view, bigger. Leaving Max or focus mode with the review open goes back to the single column and nothing is lost (your comment is still in its box).
- [ ] New PR: choose a repository, push a new branch to it from a terminal (`git push -u origin my-new-branch`), then open the *merge from* list in the island: the new branch is there (a small spinner shows while it looks) and it is the first one in the list, with "pushed a few seconds ago". Open it again after another push: still there, without choosing the repository again.
- [ ] The *merge from* list shows at most the 20 most recently pushed branches, newest first, and (when there are that many) a line saying to type to search all of them. The *into* list starts with the default branch, and the default branch is there even when it was not pushed to lately. A branch that was merged and deleted is not in either list.
- [ ] In *merge from*, type part of the name of an OLD branch (one that is not among the 20): the recent ones that match are filtered at once, a small spinner shows, and about a second after you stop typing the old branch appears in the list. Keep typing quickly: nothing is asked until you pause. Capitals do not matter, and a word from the middle of the name finds it. Choose it: it works like any other, and shows (marked) the next time you open the list.
- [ ] Type something no branch has: it says no branch has that in its name. Clear the box: the 20 recent ones come back at once. Close the list while a search is waiting: nothing is asked.
- [ ] Switch your Wi-Fi off, choose a repository, then open the branch list: it says it could not load the branches and offers *Try again* (not "no other branches"); switch Wi-Fi on and press it. Do the same while typing a name: it says it could not search, with *Try again*.

## Keyboard shortcuts

- [ ] Open the island and press **F** without clicking it: nothing happens in Island (your keys still go to the app you are in; that is on purpose, so hovering the notch never steals your typing). Now **click** anywhere on the open island and press **F**: focus mode opens. Press **F** again: it leaves.
- [ ] Click the island, press **M**: the island switches to Max and back with the next **M**. **P** pins it (the pin icon fills) and unpins. **⌘,** opens Settings (from focus mode too: focus mode ends first).
- [ ] Click into a text box in the island (a task, the clipboard search, the browser's address bar) and type the word "map frog": no shortcut fires, the letters are typed. **⌘,** still opens Settings from inside a text box. In the Browser tab, click into the page and type: the letters go to the page.
- [ ] Click the island, then move the pointer away and wait for it to close: your other app has the keyboard again (type a letter and it lands there, with no click needed). Do the same with Settings open and in front: the island closing must not pull the keyboard away from the Settings window.
- [ ] M and P do nothing in focus mode (the buttons are not there). Holding F down toggles only once.

## Permissions across rebuilds

- [ ] Quit Island, run `scripts/build-app.sh` and open the new build: the line at the end says which certificate signed it, and macOS does not ask again for Calendar, Camera or folders you already allowed. Do it a second time: the same certificate again, no new questions.
- [ ] With another copy in /Applications that is signed differently, the script prints the note about it. Open both in turn to see the repeated questions the note warns about; then keep one copy only.

## Slide gestures (Tools tab)

These need a real trackpad and your fingers, so they can only be checked by hand. The gestures are on from the start; the switch in the popup turns them off.

- [ ] In the Tools tab there are four tiles in a row: the colour picker, the keyboard lock, **Slide gestures** (pink-purple) and **Tap gestures** (blue). Hovering one names it and says whether it is on. Click **Slide gestures**: a card opens over the tab (the player is behind it) with a picture of the pad, and a close button at its top right. Closing it, or leaving the tab, closes it. Hovering the tile names it; its ring is full while the gestures are on.
- [ ] With the card open, touch the pad: a dot shows where your finger is. Touch the right-hand edge at the top: the dot is at the top right (if it is upside down, the pad's up and down are the wrong way round and that needs fixing). The picture has the shape of your pad.
- [ ] With the gestures on (they are at first; switch them off and on again to check the switch), slide one finger up the right edge: the volume goes up with a small indicator under the notch, down when you slide down. The pointer stays where it was while you slide, and moves normally again the moment you lift.
- [ ] The left edge does the same for the brightness of the built-in screen.
- [ ] The top edge starts as the **keyboard light** (it is orange in the picture, with a small light symbol): slide one finger right along the top edge of the pad and the keyboard backlight gets brighter, left and it gets dimmer, with a small indicator under the notch (light symbol and a percentage). The pointer stays still while you slide. Slide to the far left: the light goes off (the symbol changes to the dim one); slide back: it comes on. After you lift your finger, the level stays (wait for the keyboard to dim by itself when idle and touch a key: it comes back at the level you set, not at some older one). If you had set the top edge to **Skip** before, it is still Skip until you pick **Keyboard** on the top edge once.
- [ ] In the Slide gestures card the five choices for an edge (Off, Volume, Brightness, Keyboard, Skip) are three on the first line and two on the second, every name in full, and the card still fits without anything cut off at the bottom. On a Mac without a backlit keyboard (or with the backlight switched off in System Settings) sliding the top edge says there is no backlight to change, once.
- [ ] Set an edge to **Skip** (the top edge, say). With a song or video playing in an app that allows moving through it, slide along that edge: it skips ahead (right) or back (left), and lands where you let go. With nothing playing the indicator says so.
- [ ] Moving the pointer normally still works everywhere, including from the very edge of the pad into the middle. Tapping and clicking on the edge still works. Two-finger scrolling near an edge does not change the volume.
- [ ] Click another edge in the picture, give it another job (or Off), reverse its direction, change the width and the speed: each takes effect straight away and is still there after quitting and opening Island.
- [ ] With the gestures on, quit Island in the middle of a slide (or switch them off): the pointer is free again.
- [ ] If macOS asks for a permission the first time (Input Monitoring or Accessibility), note what it asked for: the card says so if the pad cannot be read.

## Tap gestures (Tools tab)

Taps are on from the start, with nothing assigned. These need a real trackpad and your fingers.

- [ ] Click the blue **Tap gestures** tile (it has its own popup and its own on/off switch, apart from Slide gestures): four cards (three fingers and four fingers, double tap and triple tap) each say "Not set". With the popup open, tap the pad with three fingers twice: the "Three fingers, double tap" card lights up (after a moment, because a triple tap is also possible) and is selected, and nothing else happens. Do the same for the other three.
- [ ] Choose **Take a screenshot** for the three-finger double tap, close the popup, and tap with three fingers twice: the screenshot tools open. A single three-finger tap, a two-finger tap, a four-finger tap, three-finger swipes and normal clicking do nothing.
- [ ] Tap and hold: choose an action for **Three fingers, tap and hold** (the third card on the top row), put three fingers down together and keep them still. After about a second the action runs while your fingers are still down, and only once however long you hold. Lifting early, moving the fingers, putting them down one after another, or using two or five fingers does nothing. Do the same with four fingers on the bottom row. With the popup open, a hold selects its card even if nothing is set for it.
- [ ] Give the triple tap another job: the double tap now waits a third of a second to see if a third tap comes, and a triple tap does only the triple tap's job.
- [ ] Each action, once: Take a screenshot (the screenshot tools open), Mission Control, Open an app (Choose an app… and pick one; it opens or comes to the front), Run a Shortcut (the list shows your Shortcuts; one with Set Focus turns Do Not Disturb on and off), Lock the screen, Start the screen saver, Turn off the display, Mute or unmute, Play or pause (with something playing).
- [ ] Full screen on or off: choose it for a tap (**Allow in Accessibility…** if the popup asks), close the popup, work in an app with a normal window (Safari, Finder, Notes) and make that tap: the app goes into full screen. The same tap again brings it back. Try it with the app already in full screen first, with Finder showing no window (it says there is no window), and in an app whose window has no green button (it says the window can't go full screen). Without the permission the indicator says so.
- [ ] Copy and Paste: the popup says to allow Island in Accessibility; allow it (System Settings ▸ Privacy & Security ▸ Accessibility; it may need allowing again after Island is updated). Select text, tap to copy, click in another place, tap to paste. Without the permission the indicator says so.
- [ ] If macOS's own "Look up & data detectors" is set to three-finger tap, the popup warns about it on the three-finger cards.
- [ ] Switch the Taps switch off: no tap does anything, and the choices are still there when it is switched on again. Quit and open Island: the choices are kept.
- [ ] Sliding along an edge and tapping do not get in each other's way (a slide never taps, a tap never holds the pointer).

## Settings

- [ ] Hover-open off: the island then needs a click. The close delay changes how fast it closes.
- [ ] Sliders: the sound volume (Focus), the overall and per-app volumes (Stats), the player's progress bar and "Close delay" (Settings) are all the same system slider with the glass knob. Dragging the player's bar moves the time shown, and the song jumps when you let go.
- [ ] Tabs: grab a row by its handle (or its name) and drag it over the others: the rows slide, and the tab bar and the swipe follow the new order at once. Quit and reopen: the order is kept. "Reset to the default order" puts it back.
- [ ] Tabs: switch a tab off: it leaves the tab bar and the swipe, and its row dims. If it was the open tab, the island shows the first tab that is on. Switch it on again: it is back where it was in the order. Quit and reopen: the switches are kept.
- [ ] Tabs: switch tabs off until one is left: that last switch cannot be turned off.
- [ ] Tabs: with Shelf off, dragging a file toward the notch does not open the island. With GitHub off, clicking a pull request link in a Teams message opens it in the browser.
- [ ] "Open Island when I log in" shows up in System Settings ▸ General ▸ Login Items (it may need approving there, and works best from /Applications).

## Packaging

- [ ] `scripts/make-dmg.sh` produces `build/Island.dmg`; opening it shows Island and an Applications shortcut.
- [ ] Drag Island into Applications, open it from there, and check the items above that depend on permissions again.
