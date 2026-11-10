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

## Settings

- [ ] Hover-open off: the island then needs a click. The close delay changes how fast it closes.
- [ ] Tabs: grab a row by its handle (or its name) and drag it over the others: the rows slide, and the tab bar and the swipe follow the new order at once. Quit and reopen: the order is kept. "Reset to the default order" puts it back.
- [ ] Tabs: switch a tab off: it leaves the tab bar and the swipe, and its row dims. If it was the open tab, the island shows the first tab that is on. Switch it on again: it is back where it was in the order. Quit and reopen: the switches are kept.
- [ ] Tabs: switch tabs off until one is left: that last switch cannot be turned off.
- [ ] Tabs: with Shelf off, dragging a file toward the notch does not open the island. With GitHub off, clicking a pull request link in a Teams message opens it in the browser.
- [ ] "Open Island when I log in" shows up in System Settings ▸ General ▸ Login Items (it may need approving there, and works best from /Applications).

## Packaging

- [ ] `scripts/make-dmg.sh` produces `build/Island.dmg`; opening it shows Island and an Applications shortcut.
- [ ] Drag Island into Applications, open it from there, and check the items above that depend on permissions again.
