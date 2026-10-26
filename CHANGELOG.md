# Changelog

Every release of Dynamic Notch, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/): new features bump the middle number, fixes bump the
last one.

## [1.3.5] - 2026-10-27

### Fixed
- Dynamic Notch no longer quits right after you allow Reminders access, and the notch reopens on
  your list once you do.
- Reminders notices access you turn on in System Settings, and shows tomorrow's to-dos after
  midnight without waiting for a change.
- The Tray preview in the drop view shows your four newest files, not the four oldest.
- A long list of Shortcuts can no longer leave the list stuck loading.
- A live stream reporting a nonsense length can no longer crash the music time display.

## [1.3.4] - 2026-10-26

### Added
- **Stats.** Click the new Stats tile in the grid (or press ⌃⌥P, or use Settings › Home) and your
  memory and CPU show beside the camera whenever nothing else is going on, turning yellow and
  then red as your Mac gets busy. Click the tile again to turn it off. Click the numbers in the
  notch to see memory, CPU, free disk space and network speed. Everything is read on your Mac and
  never leaves it.
- **Format your notes.** Notes has a colour dot and A, B, I and U at the bottom: bigger text, bold,
  italic, underline and colours. Formatting is kept across launches.

### Changed
- The grid shows five tiles to a row and scrolls to more pages, with dots on the right.
- Dragging files to the notch looks cleaner: a dashed blue Files Tray on the left, with the files
  already in it peeking out, and a solid blue AirDrop on the right.

## [1.3.3] - 2026-10-25

### Changed
- **A real notch on every screen.** Screens without a notch, like an external monitor, now get a
  notch at the top centre instead of a floating island. It stays out of sight until something's
  going on, like music, a timer or a call.
- **Rest your pointer to bring it out.** On a screen without a notch, rest your pointer at the top
  centre for a moment (the same delay as hover, 0.4 seconds by default) and the notch slides down.
  Click it to open Home, or with Hover on it opens by itself. Move away and it slides back up, and
  the menu bar underneath keeps working until then.
- **Smoother animations.** Opening has a little give, like the iPhone's island, and what's inside
  now grows out of the notch instead of popping in. Closing slides the notch smoothly back into
  the edge with crisp outlines, and switching between Home, Tray and Clipboard is a soft
  crossfade.
- The floating pill style is gone, along with its position settings, so Settings › Appearance is
  simpler. If you were using it, you'll see the notch style instead.

## [1.3.2] - 2026-10-25

### Fixed
- Connecting Calendar or Reminders could look like it did nothing: you clicked Allow, and the notch
  still asked you to connect. It now shows your calendar and to-dos as soon as you allow access.
- Everything you open from the notch (Home, Tray, Clipboard, Calendar and the rest) now sits evenly
  inside it, instead of crowding up against the top.
- The empty Tray had a stray line about a browser. It now says files stay until you quit and your
  originals aren't touched.

## [1.3.1] - 2026-10-25

You can install this from Settings › About › Install and Relaunch. If your button says Download
instead, grab this version by hand once and drag it into Applications. From then on, updates
install right from Settings, and each one is checked before it's installed.

### Fixed
- When a copy of the app can't update itself (for example a build you made yourself), the update
  button now says Download instead of Install and Relaunch, since it opens the download page.

## [1.3.0] - 2026-10-25

### Added
- **Several apps playing at once.** When a second app starts playing music or video while the
  first keeps going, the music view shows a button for each so you can switch between them.
- **Click or hover.** Settings › General has a simple choice for how the notch opens: click it,
  or just rest the pointer on it. With Hover, you can also pick how quickly it opens (0.1 to 0.5
  seconds). If you had "Expand on hover" on, you're already set to Hover.
- **Drop whole windows into Tray.** Drag a saved Pages, Numbers, Keynote, TextEdit, Safari or
  Chrome window by its title bar onto the notch and it lands in Tray. macOS asks for
  Accessibility access the first time, and some apps ask for Automation access too.
- **Choose your screen.** Settings › General › Display lists your screens by name, plus All
  displays. With All displays, music, timers and alerts show on every screen, and whatever you
  open appears on the screen you're using.
- **Links in Tray.** Drop a web link onto Tray and it's kept as a shortcut you can drag out later.

### Changed
- **A nicer island on other screens.** On displays without a notch, the floating island is now a
  rounded rectangle in a very dark grey, so it stands out on bright wallpapers. The notch on your
  MacBook stays pure black.
- **Safer updates.** Every update is signed, and the app checks that signature before installing
  anything, so a tampered download can't sneak in.
- **Tray is now a scratch space.** It holds up to 30 items and empties when the app quits. Your
  original files are never touched.
- The timer row in Home is tidier: "Timer ›" opens the full timer, and 5m, 10m, 15m and Focus
  start one straight away. The Calendar and Shortcuts rows match it.
- The Calendar panel looks like Apple's Calendar widget: the month name in red, a dot under days
  with events, and Up Next with each event's calendar colour. Click an event to open it in
  Calendar. It now shows the whole coming week, including all-day events.
- The back arrow is a plain chevron that highlights under the pointer, like macOS toolbars.
- The feature grid has more room: taller tiles, lighter type and a small coloured dot for what's
  on right now.
- The notch stays on your MacBook's screen again by default instead of following the pointer to
  other displays. Choose Follow the pointer in Settings › General if you want that.

### Fixed
- Connecting Calendar, Reminders or the camera could seem to do nothing, because the permission
  dialog didn't always appear while the app sat in the background. The app now comes forward to
  ask, and if macOS already has an answer on file it opens the right switch in System Settings.
- If Calendar access was off, the Calendar row disappeared from Home with no way to turn it on.
  It now stays, with an Allow Access button. "Add Events Only" access is explained too.
- After connecting Calendar, nothing showed up on a day with no more events. The Calendar row now
  always shows once connected, and the notch opens on your calendar right after you allow access.
- Dropping several files at once, or one after another, now adds every file to Tray, and
  documents from Pages and other apps drop in properly.
- Dragging a browser or editor window no longer drops the app itself into Tray by mistake.
- Hover didn't open the pill while it was showing on its own (Show when idle, or while trying
  sizes in Settings › Appearance). It now opens at every size, and the whole hover puff around
  the notch counts, not just the camera housing.
- Very long song titles or huge album art from a music app can no longer slow the app down.

## [1.2.0] - 2026-10-24

### Added
- **Everything in one grid.** The grid button at the top right shows every feature as a tile,
  each with a keyboard shortcut (⌃⌥ + a letter, like ⌃⌥R for the timer).
- **Clipboard.** A tab with the last 20 things you copied. Click one to copy it again. Passwords
  from password managers are skipped, and the history is never saved to disk.
- **Scratchpad.** A quick notes pad in the grid. It saves as you type and stays open while you
  write. Press Escape or click outside to close it.
- **A new Timer panel.** Pick Timer, Pomodoro or Stopwatch, slide the ruler to any length and
  press Start. Open it from the timer icon or the ••• button in Home.
- **Pomodoro.** Tap Focus in Home for a 25 minute session. When it ends, the notch offers a
  5 minute break, then the next session. You can change both lengths in Settings.
- **Stopwatch.** Counts up next to the camera, with pause and reset.
- **Calendar panel.** Click your next event in Home to see this month and what's coming up.
- **Reminders.** Today's to-dos from the Reminders app. Click the circle to tick one off.
- **Mute your mic during calls.** A mute button in the call view that works for every app.
- **Keep Awake.** A tile in the grid that stops your Mac from sleeping.
- **Finished downloads.** Turn it on in Settings › Home and the notch tells you when a file lands
  in Downloads. Click to show it in Finder or drag it straight out.
- **Gestures.** Swipe sideways on the music to skip songs, pull down on the notch to open it and
  push up to close it.
- **Second screens.** The notch follows your pointer to other displays, where it shows as a
  floating island.
- **Updates inside the app.** Once a day it checks GitHub for a new version and can install it
  for you. You can turn this off in Settings › About.
- **Homebrew.** Install with `brew install --cask shandilyaswagat/tap/dynamic-notch`.
- The first-launch hello greets you by your first name, with a waving hand.

### Changed
- Only Home, Tray and Clipboard sit in the tab bar; everything else is in the grid, so the top
  right has just the grid and Settings.
- A running timer looks like the iPhone's: pause and cancel on the left, the time on the right.
  Every kind of timer uses the same orange.
- The quick timers in Home are now 5, 10 and 15 minutes, plus Focus and ••• for anything else.
- The battery is gone from the top of Home, since it's already in your menu bar.

### Fixed
- While music (or a timer, call or stopwatch) was open, there was no way back to Home and the
  other features. Every open activity now has a back arrow at the top left.
- After a while (sooner if you connect headphones or join calls often) the app could get stuck
  using a full CPU core and stop responding, including the menu bar icon.

## [1.1.0] - 2026-10-21

### Added
- **File Tray.** Drag files onto the notch and drop them on Tray to keep them handy. Drag them
  back out whenever you need them, double-click to open, right-click for more.
- **Mirror.** A quick camera preview in the notch so you can check how you look before a call.
  The camera only turns on while you're looking at it.
- **Calendar.** Your next event shows up in Home, and the notch gives you a heads up 5 minutes
  before it starts.
- **Shortcuts.** Pin up to 4 of your shortcuts to Home and run them with one click.
- **Volume and brightness.** The notch shows the level when you change them.
- **Battery level** in Home.
- **Hover to open.** With "Expand on hover" on, resting on the notch opens Home.
- Home now has tabs (Home, Tray, Mirror) and a new layout: wider and shorter, with your music on
  the left and everything else next to it.
- A new Home tab in Settings to turn each of these on or off.

### Changed
- Dropping files on the notch now gives you two choices: Tray or AirDrop.
- The app asks for camera access only when you open Mirror, and calendar access only when you
  click Connect.

## [1.0.0] - 2026-10-21

### Added
- First release. The notch grows to show music, timers, calls, charging, low battery,
  headphones and AirDrop.
- Small, Medium and Large sizes, plus width and thickness fine-tuning.
- Pitch black look so the extension blends into the notch.
- Optional floating pill style.
- Menu bar icon, Settings window, open at login.

[1.3.5]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.5
[1.3.4]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.4
[1.3.3]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.3
[1.3.2]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.2
[1.3.1]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.1
[1.3.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.0
[1.2.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.2.0
[1.1.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.1.0
[1.0.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.0.0
