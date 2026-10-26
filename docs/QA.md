# QA report: version 1.1.0

Tested 2026-10-21 on a MacBook Air M2 (Mac14,2, 179 × 32 pt notch), macOS 27.0, Xcode 26.4.1,
with a second display attached. Three passes: first build, rename to Dynamic Notch, and a
full bug-hunt and optimization pass (§5). Every pass ended with a clean rebuild and all checks
below.

## 1. Automated checks

Run them all with `./Scripts/check.sh`.

| Check | Result |
|---|---|
| Unit tests (Swift Testing), 125 tests in 23 suites | ✅ all pass |
| Release build with warnings as errors (Swift and Objective-C) | ✅ zero warnings |
| Universal binary (arm64 + x86_64) | ✅ |
| Hardened runtime signature, `codesign --verify --deep --strict` | ✅ |
| DMG created and `hdiutil verify` checksum | ✅ valid |
| Debug-only hooks absent from release binary | ✅ |

What the tests cover: presentation rules and priorities, swipe order, both layout styles (every
shape fused to the top edge, centred on the notch, camera kept clear, thickness floor, hover
growth, displays without a notch), all three size modes, the fixed window, the shape outline, alert
queue timing, coalescing and urgent take-over, countdown maths, battery alert thresholds, time
formatting, media-helper parsing (split reads, garbage, runaway output, artwork tint), playback
position, the play/pause flicker guard, artwork ownership, call-app and headphone classification,
liquid-effect maths, settings persistence and recovery from corrupt values, timer completion, and
the island model (expand/collapse, alerts waiting and interrupting, disabled activities, notch
hover, drag-to-AirDrop zone, preview, live size changes). Added in 1.1: the file tray (adding,
duplicates, capacity, saving across launches, files that moved), calendar rules (next event,
5-minute heads-up, labels), the fixed-size nook, volume and brightness alerts (instant, never
replayed, kept out of expanded views), drop zones, dragging out of the tray, tabs and
favourite shortcuts.

## 2. On-screen verification

Each state was triggered on the real notch with debug-build commands and checked in screenshots.

| State | Result |
|---|---|
| First launch: "Hi <first name>" with a waving hand | ✅ |
| Idle: nothing drawn, screenshots clean | ✅ |
| Compact timer, ears either side of the camera | ✅ all three sizes |
| Expanded timer, Timer done with Repeat / Stop | ✅ |
| Now Playing compact and expanded, artwork tint, progress | ✅ all three sizes, release build |
| Same artwork after the player quits and returns | ✅ (after fix) |
| Live stream with no length: `0:00` and `--:--`, helper keeps running | ✅ (after fix) |
| Two activities: bubble beside the notch; swipe swaps them | ✅ |
| Home: last media + timer presets | ✅ all three sizes |
| Charging, low battery, headphones alerts | ✅ all three sizes |
| AirDrop drop target, normal and targeted | ✅ |
| Home nook: tabs and battery beside the camera, media card plus calendar, timers and shortcuts | ✅ all three sizes |
| Tray: empty state, files with thumbnails, count badge | ✅ |
| Mirror: camera prompt (camera itself not switched on during QA) | ✅ |
| Drop target with Tray and AirDrop halves | ✅ |
| Clipboard: cards, app name and age, clear button (1.2) | ✅ |
| Notes: placeholder, text cursor shows when opened (1.2) | ✅ |
| Focus: chip in Home, indigo countdown, "Take a break" alert with Break and Stop (1.2) | ✅ |
| Home timer row fits at Small and Large with the Focus chip (1.2) | ✅ |
| Volume indicator from a real volume change | ✅ |
| Brightness indicator from a real brightness change | ✅ (after fix) |
| Calendar heads-up and shortcut-finished alerts | ✅ |
| Settings › Home tab, with the real Shortcuts list | ✅ |
| Downloaded (quarantined) app: Now Playing works, no extra warning | ✅ (after fix) |
| Settings: General, Appearance (live preview), Activities, About | ✅ |
| Animation: grows out of the notch, no gap at the top edge | ✅ frame-by-frame from a screen recording |

## 3. Performance (release build)

| State | App CPU | Wakeups / s | Memory | Media helper |
|---|---|---|---|---|
| Idle | 0.0 % | 0–1 | 15 MB | 0.0 %, ~5 MB |
| Compact timer | < 1 % | — | 19 MB | — |
| Music playing, compact | ~0 % (bars run in the system render server) | 0 | 20 MB | 0.1 % |

## 4. Memory leaks

Checked with `leaks` and malloc stack logging after running every state twice. 417 small blocks
(26 KB) are reported, all inside Apple's App Intents framework (three `com.apple.linkd` XPC
connections it opens at launch). The count does not grow between rounds. No leaks from Dynamic
Notch's own code.

## 5. Bugs found and fixed

| Bug | Fix |
|---|---|
| Timer chips wrapped to two lines | 5 presets, single-line chips that shrink to fit |
| Settings window titled "Untitled"; General tab cut off; ticks on every slider step | Titles, taller tab, continuous sliders |
| Headphone name truncated too early | Wider alert ears |
| Resting shape showed as a black block in screenshots and recordings | Transparent at rest |
| Now Playing bars cost ~5 % CPU | Core Animation loop |
| Haptic tap on every hover | Haptics only for deliberate actions |
| Media helper crashed on live streams (NaN/infinite length or position) | Only finite numbers are sent; JSON validated before writing |
| Artwork missing when the same art came back after a player quit or a track without art | Helper forgets sent art when a track has none; app asks for a resend once if art is missing |
| Long timers could ring many seconds late (default sleep tolerance) | 20 ms tolerance |
| An alert could get stuck if its expiry fired early (clock change) | Expiry is re-armed until the alert is really gone |
| "Timer done" waited up to 3 s behind another alert | Urgent alerts take over; the other comes back after |
| "Timer done" stayed expanded forever on an unattended Mac | Clears itself after 10 minutes |
| With three activities, swiping only alternated between two | Swipe steps through all of them |
| Dragging the width slider made the shape jitter sideways | Fixed full-width window |
| Clicks in the Settings window didn't collapse an expanded notch | Counted as outside clicks |
| Hidden bubble (a 1 pt point inside the shape) could steal a click | Not hit-testable unless shown |
| Play/pause icon could flip back for a moment after clicking | Stale helper updates ignored for 1.5 s |
| Login item stuck "on" if it needed approval in System Settings; state could go stale | Synced on open, approval note and "Open Login Items" button |
| Appearance ranges used the display size from when Settings first opened | Read live |
| Album art decoded and tinted on the main thread | Done on a background queue |
| Layout maths ran on every mouse move anywhere on screen | Skipped unless the pointer is near the notch |
| Progress timer ticked while paused; call polling every second during long calls | Paused while paused; 3 s once a call is established |
| Downloaded copies: macOS blocked the Now Playing helper with a second "Not Opened" warning | The app loads its own unquarantined copy of the helper |
| Brightness changes never reached the app (Swift 6 made the callback main-actor isolated) | Plain global callback function |
| Event and shortcut names cut short in alerts; "Tray" tab squeezed to "Tr…" | Wider alert sides; tabs keep their full size |
| Home grew taller with every feature | Fixed-size wide nook, widgets side by side |
| `swift build` failed to link with the macOS 27 Command Line Tools SDK | Scripts pin the selected Xcode's SDK |

## 6. Not verified here — please check by hand

macOS blocks synthetic mouse events from automated tools without Accessibility permission, and
some events need real hardware. These paths are covered by unit tests at the model level, but not end to end:

- [ ] Hover the notch: it swells slightly. Click: Home opens.
- [ ] Click a compact activity: it expands. Click elsewhere, or move the pointer away for a
      second: it collapses.
- [ ] Right-click the shape: context menu with activity actions, Settings, Quit.
- [ ] Two-finger horizontal swipe on the shape with two activities: they swap.
- [ ] Drag a file from Finder to the notch: drop target appears; release sends with AirDrop.
- [ ] Scrub the Now Playing progress bar; play/pause/skip in Music, Spotify and a browser.
- [ ] Join a FaceTime / Zoom / Meet call: green call activity with a running time after ~2 s.
- [ ] Plug in power: Charging alert. (Low battery alerts fire at 20 % and 10 %.)
- [ ] Connect AirPods: Connected alert.
- [ ] Open at login: switch on, log out and in.
- [ ] Full-screen video, Mission Control, switching Spaces: shape stays on top and correct.
- [ ] Close the lid with an external display, then reopen: the app follows the display change.
- [ ] Sleep with a timer running past its end: alert on wake.
- [ ] Drag a file onto the notch, drop on Tray; drag it back out to the desktop.
- [ ] Open Mirror and allow the camera: live preview; camera light goes off when you leave.
- [ ] Copy some text, open Clipboard, click a card, paste it somewhere.
- [ ] Copy a password from a password manager: it must not show up in Clipboard.
- [ ] Open Notes, type, press Escape: the app you were in still gets your typing afterwards.
- [ ] Quit and reopen: the note is still there.
- [ ] Grid button: every tile opens its view; each ⌃⌥ shortcut works from another app.
- [ ] Reminders: Connect, tick one off, it's done in the Reminders app.
- [ ] With an external display chosen in Settings: nothing shows at rest; rest the pointer at the top centre and the notch slides down after the hover delay; click opens Home; move away and it slides back up. A running timer shows there as a notch.
- [ ] Updates: with an older build installed, Settings › About › Check Now offers the new version and Install and Relaunch works.
- [ ] Homebrew: `brew install --cask shandilyaswagat/tap/dynamic-notch` installs and opens without the Open Anyway step.
- [ ] Timer panel: drag the ruler both ways; it follows the pointer and settles on a minute.
- [ ] Two-finger swipe on music skips; pull down opens; push up closes.
- [ ] Mute the mic during a real call; the other side can't hear you; unmute works.
- [ ] Keep Awake on: the display doesn't sleep; off: it does.
- [ ] (1.4.0, debug builds) Settings › Appearance › Elongated: Home, Tray, Clipboard and the grid stretch across the top; scroll the widget row sideways; open Calendar from it and the shape narrows; back returns to the wide Home.
- [ ] (1.4.0, debug builds) Elongated widgets: drag the music knob; click Mirror for the live circle; tap days in the strip; Join on an event with a Zoom/Meet link opens the call; type and format a note (B, I, U, A, colour) and see it kept in the Notes panel; spin the timer wheels, 1m/5m, start; add, tick and delete a to-do; while typing, moving the pointer away doesn't close the notch; Escape does.
- [ ] Grid: five tiles per row; scroll down to page 2 (Stats); the dots follow; clicking a dot jumps there.
- [ ] Stats tile: click once and MEM/CPU appear beside the camera (tile shows its dot); click again and they go.
- [ ] Settings › Home › Stats on: MEM and CPU show beside the camera; they match Activity Monitor roughly; a timer replaces them and they come back when it ends; click opens the Stats panel; turning Stats off hides it all.
- [ ] Turn on Finished downloads, download a file: the heads-up shows, drag it out works.
- [ ] Start Focus, let it run out (or set it short in a debug build): Break and Stop work.
- [ ] Connect Calendar and allow access: next event shows; heads-up 5 minutes before.
- [ ] Pin a harmless shortcut in Settings › Home and run it from Home.
- [ ] Press the volume and brightness keys: the notch shows the level.

## 7. Known limitations

* Now Playing depends on the MediaRemote helper. If a future macOS blocks it, Now
  Playing disappears and everything else keeps working.
* The app can't tell which app is using the camera, only that one is.
* AirPods battery levels are not shown (needs Bluetooth permission and private keys).
* Not on the Mac App Store.
* The notch's volume and brightness indicator appears next to macOS's own indicator; macOS has
  no supported way to hide its own.
* Not built: other apps' notifications, Lock Screen display, weather and keyboard backlight.
  See [Research](RESEARCH.md) §5 for why.
* Tested only on macOS 27. The minimum target is macOS 14; versions 14–26 have not been run.
