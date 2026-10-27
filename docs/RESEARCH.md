# Research: what the Dynamic Island does, and what moves to the Mac

This is the inventory the app was designed from. It lists what the iPhone Dynamic Island does,
then says for each item whether it can come to a MacBook, and how.

## 1. The request

From the Threads comment that started this project:

> Dynamic Island for Mac with notches, to be under notch, options to make it wider / less
> wide and thicker / thin or higher/lower … tons of notch apps for Mac saying Dynamic Island
> which they aren't … Dynamic Island for Mac aka dynamic PILL.

Read as requirements:

| # | Requirement | How it is handled |
|---|-------------|---------------------|
| R1 | A real island that behaves like the iPhone's, not a static drawer | Compact, minimal, expanded and alert presentations with live activities |
| R2 | Lives at the notch | The notch itself grows (default); a floating pill is an optional style |
| R3 | Width, thickness, vertical and horizontal position are adjustable | Size modes, sliders and live preview in Settings › Appearance |
| R4 | Looks like Apple made it; the extension reads as the notch itself | Pitch black surface, notch-shaped outline, spring and liquid motion |

The project later settled on a **dynamic notch** (the notch itself grows) rather than a floating
island; that is the default, with the floating pill kept as an option.

## 2. How the iPhone Dynamic Island works

### 2.1 Presentations (from ActivityKit / Human Interface Guidelines)

| Presentation | What it looks like | When |
|---|---|---|
| **Compact** | Pill wider than the camera cutout; a *leading* view on the left, a *trailing* view on the right, nothing in the middle | One live activity |
| **Minimal** | A small detached circle beside the main pill | A second live activity is running |
| **Expanded** | Large rounded rectangle with leading, trailing, center and bottom regions | Long-press, or important updates |
| **System alert** | Pill briefly grows to show a short status (charging, silent mode, AirPods connected, Face ID) then shrinks back | System events |

### 2.2 Interactions

| iPhone gesture | Result |
|---|---|
| Tap | Opens the owning app |
| Long-press | Shows the expanded view |
| Swipe toward the center | Hides the activity into the minimal view |
| Swipe outward | Brings it back |
| Tap outside | Collapses the expanded view |

### 2.3 Motion

* Shape changes use a soft spring with a little overshoot. The island never "teleports".
* When a second activity appears, a droplet pinches off the main pill (a metaball / "goo" effect).
* Content blurs and scales out while new content blurs in. Old and new content never sit
  side by side.
* Pure black, so the island blends with the camera hardware.

### 2.4 System activities on iPhone

Music / Now Playing, Timer, Phone & FaceTime calls, Screen recording, Charging,
Low battery, Silent mode switch, AirPods connected (with battery), Face ID, Apple Pay,
AirDrop progress, Personal Hotspot, Voice Memos recording, Maps navigation, Focus change,
Shazam, Find My alerts, and third-party Live Activities (sport scores, food delivery, rides).

## 3. Transfer analysis for macOS

Legend: **Yes** = shipped in 1.0. **Later** = possible but not in 1.0. **No** = macOS gives no
reliable way to do it.

| iPhone feature | Mac | How / why |
|---|---|---|
| Now Playing (music, podcasts, video) | **Yes** | MediaRemote via a small helper process. Works for Music, Spotify, browsers, Podcasts, etc. |
| Timer | **Yes** | Clock.app has no API, so the app has its own timer |
| Calls (FaceTime, Zoom, Meet…) | **Yes** | Core Audio tells us which app is using the microphone; Core Media IO tells us the camera is on. Shown as a call with a running duration |
| Charging | **Yes** | IOKit power-source notifications |
| Low battery (20 %, 10 %) | **Yes** | IOKit |
| AirPods / headphones connected | **Yes** (without battery %) | Core Audio default-output change + Bluetooth transport type. Battery needs Bluetooth permission and private keys, so it is left out |
| AirDrop | **Yes**, adapted | iPhone shows AirDrop progress. On the Mac, the pill becomes a drop target while you drag files near the notch, then sends them with AirDrop |
| Expanded view on long-press | **Yes**, adapted | Click expands; pointer leaving or clicking elsewhere collapses |
| Swipe between activities | **Yes**, adapted | Two-finger horizontal swipe on the pill swaps which activity is in front |
| Split into minimal bubble | **Yes** | Second activity becomes a detached bubble with the liquid split animation |
| Silent mode | **No** | Macs have no ring switch. Mute already shows a system HUD; repeating it would be noise |
| Volume / brightness HUD | **No** | The system HUD cannot be hidden cleanly, so we would show it twice |
| Face ID / Touch ID | **No** | No API |
| Apple Pay | **No** | No API |
| Screen recording | **No** | No public API to see that another app is recording |
| Focus mode changes | **No** | No public API for third-party apps |
| Notifications | **No** | Apps cannot read other apps' notifications |
| Third-party Live Activities | **No** | ActivityKit does not exist for third-party Mac apps |
| AirPods battery | **Later** | Needs Bluetooth permission and private IORegistry keys |
| Calendar "up next" | **Later** | Needs Calendar permission; not part of the iPhone island |
| Voice Memos recording | **Yes** (as microphone use) | Covered by the microphone activity: shows the app and duration |

## 4. Mac-specific facts we measured (MacBook Air M2, macOS 27)

* Notch: 179 × 32 pt on a 1470 × 956 pt screen (`NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`, `safeAreaInsets.top`).
* Calling `MRMediaRemoteGetNowPlayingInfo` from our own process returns nothing (blocked
  since macOS 15.4). The same call from inside `/usr/bin/perl` returns full track info.
  `MRMediaRemoteSendCommand` returns success from either.
* Core Audio process objects (`kAudioHardwarePropertyProcessObjectList`,
  `kAudioProcessPropertyIsRunningInput`) report which process holds the microphone, with no
  permission prompt.
* Metal shader compilation is not available without an extra Xcode download, so the liquid
  effect uses SwiftUI `Canvas` filters, not a custom shader.

## 5. What the paid notch apps charge for (researched for 1.1.0)

| Feature | Sold in | Dynamic Ledge |
|---|---|---|
| Now Playing with controls | NotchNook ($25), Alcove ($14), DynamicLake Pro ($14–17), MediaMate (~$7) | ✅ since 1.0 |
| File tray / shelf | NotchNook (Tray), DynamicLake (DynaClip, DynaDrop) | ✅ 1.1 |
| AirDrop by dropping on the notch | NotchNook | ✅ since 1.0 |
| Mirror (camera preview) | NotchNook | ✅ 1.1 |
| Calendar: next event and alerts | NotchNook, Alcove, DynamicLake (DynaGlance) | ✅ 1.1 |
| Run Shortcuts | NotchNook | ✅ 1.1 |
| Volume and brightness indicator | Alcove, DynamicLake (DynaKeys), MediaMate | ✅ 1.1 (shown alongside the macOS indicator) |
| Calls and meetings | DynamicLake | ✅ since 1.0 |
| AirPods / Bluetooth connect | DynamicLake (DynaConnect) | ✅ since 1.0 |
| Timer / focus timer | DynamicLake | ✅ since 1.0 |
| Battery status | Alcove | ✅ 1.1 (in Home) |
| Open on hover, swipe gestures | NotchNook, Alcove | ✅ |
| Size and look customisation | All | ✅ |
| Other apps' notifications in the notch | Alcove, DynamicLake | ❌ needs Accessibility access to read Notification Center; fragile across macOS versions |
| Showing on the Lock Screen | Alcove, DynamicLake | ❌ needs private window-server tricks |
| Weather | DynamicLake (DynaGlance) | ❌ needs the internet; the app works fully offline |
| Hiding the macOS volume indicator | MediaMate | ❌ no supported way; the notch indicator shows next to it |
| Keyboard backlight control | MediaMate | ❌ no public API |

Prices are from reviews and store pages in October 2026 and may change.

## 6. More competitors (researched for 1.2.0)

A second look, past the four big paid apps, at what free and newer notch apps add.

| App | Price | What it adds |
|---|---|---|
| Boring Notch | Free, open source | Music with visualizer, calendar, file shelf with AirDrop, HUD replacement, battery, mirror |
| Atoll | Free, open source | System stats, clipboard history, color picker, timers, Focus and screen-recording indicators, lock screen widgets |
| NotchNest | One time purchase | Clipboard with search and pinning, quick notes, Pomodoro timer |
| Itchy | Free | Twelve modules including Pomodoro, notes, clipboard, mail |
| NotchBox | Paid | Clipboard, Pomodoro, notes, water tracking, bookmarks |
| NotchDodo | Paid | Clipboard history that skips password-manager copies, focus sounds |
| ComfyNotch | Free, open source | Widgets, music, brightness and volume |
| QuakeNotch | Freemium | A terminal that slides down from the notch |
| DropNotch | Free | AirDrop, Mail and Messages drop zone |

**Picked for 1.2.0**, because almost every newer app has them and they fit a small, quiet nook:

| Feature | Seen in | Dynamic Ledge |
|---|---|---|
| Clipboard history | Atoll, NotchNest, Itchy, NotchBox, NotchDodo | ✅ Text only, last 20, memory only, private copies skipped |
| Quick notes | NotchNest, Itchy, NotchBox, Crest | ✅ One scratchpad, saved as you type |
| Pomodoro / focus timer | NotchNest, Itchy, NotchBox, NotchFlow | ✅ Focus then break, built on the existing timer |

**Left out on purpose:** system stats, color picker, terminal, water tracking and bookmarks (niche,
and each one adds clutter to a small space); weather and AI features (need the internet);
Focus-mode and screen-recording indicators (no public API).


## 7. Vorssaint (researched for 1.2.0)

Vorssaint is a free, open-source all-in-one Mac utility whose "Dynamic Island" is one optional
module among window, mouse, sound, cleaning and system-monitor tools.

**Taken:** swipe on the music to change tracks and scroll to open or close; stopwatch and focus
sessions next to the timer; a month calendar with upcoming events; muting the microphone from
anywhere; keeping the Mac awake; a heads-up for newly arrived files in Downloads.

**Left out:** lyrics and AI-agent tracking (need the internet); other apps' notifications
(unreliable); connected accessory battery (needs Bluetooth access; maybe later); everything that
isn't a notch feature (window snapping, fan control, cleaners, uninstallers).

## 8. Boring Notch (researched for 1.2.0)

Free and open source: music with a visualizer, calendar, file shelf with AirDrop, mirror,
charging, reminders, custom gestures and a replacement volume/brightness/backlight HUD; weather,
Bluetooth live activity, lock-screen widgets and an extension system are planned. It installs
with Homebrew.

**Taken:** Reminders, Homebrew install, in-app updates, an island on other displays, and (from
Vorssaint) a launcher grid of every feature with keyboard shortcuts.
**Not yet:** replacing the macOS volume/brightness HUD and keyboard backlight; a real audio
visualizer (needs recording permission); custom gestures.
