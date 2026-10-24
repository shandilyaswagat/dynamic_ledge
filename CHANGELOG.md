# Changelog

Every release of Dynamic Notch, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/): new features bump the middle number, fixes bump the
last one.

## [Unreleased]

### Added
- **Several apps playing at once.** When a second app starts playing music or video while the
  first keeps going, the music view shows a button for each so you can switch between them.
- **Click or hover.** Settings › General now has a simple choice for how the notch opens: click
  it, or just rest the pointer on it. If you had "Expand on hover" on, you're already set to
  Hover.

### Changed
- **Safer updates.** Every update is now signed, and the app checks that signature before
  installing anything, so a tampered download can't sneak in.
- The Calendar panel looks like Apple's Calendar widget: the month name in red, a dot under days
  with events, and Up Next with each event's calendar colour. Click an event to open it in
  Calendar. It now shows the whole coming week, including all-day events.
- The back arrow is a plain chevron that highlights under the pointer, like macOS toolbars.
- The feature grid has more room: taller tiles, lighter type and a small coloured dot for what's
  on right now.
- The notch stays on your MacBook's screen again by default instead of following the pointer to
  other displays. Choose Follow the pointer in Settings › General if you want that.

### Fixed
- You can now drag a document straight from an app's title bar (like Pages) onto the notch, not
  just files from Finder.
- Hover didn't open the pill while it was showing on its own (Show when idle, or while trying
  sizes in Settings › Appearance). It now opens at every size, and the whole hover puff around
  the notch counts, not just the camera housing.
- After connecting Calendar, nothing showed up in the notch on a day with no more events. The
  Calendar row now always shows once connected, and the notch opens on your calendar right after
  you allow access.
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

[1.2.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.2.0
[1.1.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.1.0
[1.0.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.0.0
