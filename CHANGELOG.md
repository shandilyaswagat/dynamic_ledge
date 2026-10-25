# Changelog

Every release of Dynamic Notch, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/): new features bump the middle number, fixes bump the
last one.

## [Unreleased]

## [1.3.0] - 2026-10-25

### Security
- Add fail-closed support for authenticated in-app updates: once a release public key is
  configured, the updater accepts only signed metadata and rejects invalid signatures and
  mismatched versions, products, sizes or hashes before mounting an update. It also verifies
  the expected Apple signing team for Developer ID installations.
- Preserve quarantine during update installation. Publishing refuses to run until a signing key
  and embedded public key are configured.
- Limit update manifests and disk images, keep release links on GitHub, and bound Now Playing
  artwork, metadata and command-pipe input to prevent malformed data exhausting resources.

### Added
- **Configurable hover delay.** When opening the notch on hover, choose how quickly it opens
  in Settings › General (from 0.1s up to 0.5s, defaulting to 0.4s).
- **Document window dragging.** Move a saved Pages, Numbers, Keynote, TextEdit, Safari, or
  Chromium-family browser window to the notch and release it over Tray. This requires
  Accessibility access and a document location exposed by the source app. iWork and browser
  fallbacks also require Automation access and one exact window-title match; unsaved or
  ambiguous windows are rejected. File and document-proxy-icon drags continue to work normally.
- **Web shortcuts.** HTTP and HTTPS links accepted into Tray become session-owned `.webloc`
  files. Browser window resolution supports Safari and Chromium-family apps when they expose
  the active tab through Automation; dragging tab content is not treated as moving a window.
- **Several apps playing at once.** When a second app starts playing music or video while the
  first keeps going, the music view shows a button for each so you can switch between them.

### Changed
- **Tray empty state.** Restored the original dashed drop card and its standard file-drop
  guidance: “Drag files onto the notch to keep them here.” The 30-item, session-only shelf
  remains in effect without adding permission controls to the Tray design.
- **Tray capacity and session shelf.** Tray holds up to 30 file references and web shortcuts for
  the current app session, avoids replacing existing items on overflow, and leaves originals
  untouched on disk. The empty Tray keeps its original file-drop design.
- **Drop destinations.** Valid file drags reveal enabled Tray/AirDrop targets; moved document
  windows offer Tray. Unsupported gestures and disabled destinations are rejected.
- **Notch opening controls.** Settings › General now offers Click or Hover as an explicit
  opening mode. Existing “Expand on hover” settings migrate automatically.
- **Document file drops.** The notch accepts file drags and document-proxy drags from apps such
  as Pages, then routes local files to Tray or AirDrop.
- The Calendar panel looks like Apple's Calendar widget: the month name in red, a dot under days
  with events, and Up Next with each event's calendar colour. Click an event to open it in
  Calendar. It now shows the whole coming week, including all-day events.
- The back arrow is a plain chevron that highlights under the pointer, like macOS toolbars.
- The feature grid has more room: taller tiles, lighter type and a small coloured dot for what's
  on right now.
- The notch stays on your MacBook's screen again by default instead of following the pointer to
  other displays. Choose Follow the pointer in Settings › General if you want that.

### Fixed
- Clarify that saved open-document windows can be added to Tray and remove error-message
  wording that directs users to Finder as the required way to add a document.
- Reveal file-drop targets during source-app tracking loops independently of mouse-drag
  callbacks, and keep native destinations active until AppKit completes the drop.
- Accept moved document windows across the highlighted notch target, including the top edge;
  preserve source-window mouse events and retain confirmed movement until release.
- Accept individual file/URL pasteboard representations as well as bridged URL objects.
- Prompt for macOS Accessibility access when an open window is released over Tray without
  permission. Keep permission controls in Settings and Tray, and remove the permission banner
  from the drag target. Finder file drops do not require this permission.
- Verify that different Pages documents, including identically named files in different folders,
  are accepted separately; duplicate detection uses the full file URL, not its extension.
- Build universal binaries with native per-architecture SwiftPM builds and preserve the packaged
  app metadata for update signing. Sign in temporary staging to avoid Finder metadata errors.
- Keep web shortcut files unique, bounded by accepted tray items, and clean them on removal.
- **Sequential and multi-file drops.** Dragging multiple files or adding several files in a row
  from Finder now reliably adds each individual file to the Tray shelf instead of misidentifying
  the folder or rejecting subsequent drops as duplicates.
- **Application bundle fallbacks for document apps.** Dragging document editors or web browser
  windows no longer falls back to adding the browser or editor application executable to the Tray.
- With Expand on hover, resting the pointer on the pill didn't open it while the pill was showing
  on its own (Show when idle, or while trying sizes in Settings › Appearance). It now opens at
  every size, and the whole hover puff around the notch counts, not just the camera housing.
- After connecting Calendar, nothing showed up in the notch on a day with no more events. The
  Calendar row now always shows once connected, and the notch opens on your calendar right after
  you allow access.

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

[1.3.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.3.0
[1.2.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.2.0
[1.1.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.1.0
[1.0.0]: https://github.com/shandilyaswagat/dynamic_notch/releases/tag/v1.0.0
