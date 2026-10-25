# Design spec

The goal: someone who owns an iPhone should look at the notch and assume Apple shipped it.
All numbers are in points. Constants live in `Sources/NotchKit/Core/IslandMetrics.swift`;
change them there, then update this file.

## Size modes

| Mode | Scale | Notch ears (default width) | Expanded width | Now Playing height |
|---|---|---|---|---|
| Large (default) | 100 % | 47 pt | 390 pt | 140 pt content |
| Medium | 90 % | 42 pt | 351 pt | 126 pt content |
| Small | 80 % | 38 pt | 312 pt | 112 pt content |

The scale applies to ears, alert ears and height, expanded width, content heights, paddings,
bottom corner radius, the bubble, and every font, icon, button and gap inside. The numbers in the
rest of this file are the Large design. Compact thickness is never scaled below the notch height.

## Notch style (default)

The shape is fused to the top edge of the screen and grows out of the notch.

```
 ──╮                                   ╭──   ← concave shoulders (6 pt compact, 10 pt expanded)
   │  ◉ leading  [ camera ]  trailing ◉ │   ← compact: content in the ears beside the camera
   ╰────────────────────────────────────╯   ← rounded bottom corners
```

| Element | Size | Corners |
|---|---|---|
| Hidden | inside the real notch, fully transparent | — |
| Hover on the notch | notch + 20 wide, + 3 tall | shoulders 5, bottom 11 |
| Compact | notch + 2 × ear, height = max(thickness, notch height) | shoulders 6, bottom min(0.42 × h, 14) |
| Ear width | `round(h × 1.15) + (width − 180) / 2`, at least 80 % of that slot | — |
| Alert | notch + 2 × max(ear, 128), compact height + 6 | shoulders 6, bottom min(0.42 × h, 16) |
| Expanded | width max(clamp(width + 190, 360, 560), compact + 40); height = notch + 2 + content + 14 | shoulders 10, bottom 30 |
| Minimal bubble | circle, compact height − 6, 4 pt right of the shape, vertically centred on the strip | — |
| Hover lift | +3 each side, +2 at the bottom; the top never moves | — |

Expanded content heights: Now Playing 140 · Timer 72 · Call 72 · Home 84 (144 with media) ·
Drop 100 · Timer done 72. The strip beside the camera stays empty in expanded views.

## Displays without a notch

External monitors (and Macs without a notch) get a virtual notch at the top centre: 180 pt wide,
as tall as the menu bar but never under 32 pt, so everything sits exactly as it does on a
MacBook. Nothing is drawn while nothing is happening; at rest the shape is retracted into the
top edge of the screen.

* Live activities and alerts grow out of the top edge the same way they grow out of the notch.
* Resting the pointer on the notch's spot for the hover delay (0.4 s by default) slides the notch
  down (notch + 20 wide, + 3 tall). Until then the menu bar underneath keeps its clicks.
* Click it to open Home. With Hover chosen in Settings, it opens Home after another hover delay.
* Moving away slides it back up into the edge.

## The nook: Home, Tray and Mirror

Clicking the notch opens a fixed-size "nook", the same size for all three tabs so switching never
resizes it.

| Element | Large |
|---|---|
| Width | 560 (or compact + 40 if wider) |
| Body below the camera line | 120, starting 10 below the strip (notch style) so it sits evenly between the strip and the bottom edge |
| Total height, notch style | notch height + 2 + 10 + 120 + 14 = 178 on a 32 pt notch |
| Tabs | in the strip left of the camera; the selected tab shows its name, others an icon |
| Tabs | Home, Tray and Clipboard left of the camera; Notes, Mirror and Settings right of it. Each side gets exactly half the room; if the selected tab's name doesn't fit, every tab on that side shows just its icon |
| Home body | media card (210 wide) on the left; calendar, timers and shortcuts as 30 pt rows on the right |
| Tray body | one scrolling row of 52 pt icons with names, clear button on the right |
| Mirror body | 16:9 camera preview on the left, message and button on the right |
| Clipboard body | one scrolling row of 150 pt text cards (4 lines, app and age below), clear button on the right |
| Notes body | one text area filling the body; the panel takes the keyboard only while this tab is open |
| Focus | indigo (Focus) and green (Break) versions of the timer; same shapes as the orange timer |

Medium and Small scale all of it.

## Surface

* Pitch black (default): pure `#000000`, no shadow, no outline.
* Pitch black off: shadow black 35 %, radius 18, y 8 (scaled down for compact shapes), and a
  0.5 pt outline at 7 % white.

## Type

SF Pro (system font) throughout. All changing numbers use monospaced digits so they don't jitter.

| Use | Size / weight |
|---|---|
| Compact labels and countdowns | 0.4 × thickness, 11–18, semibold; shrinks to fit its ear |
| Alerts | 14 semibold (headphone name 13) |
| Expanded title | 15 semibold |
| Expanded secondary | 13 regular, 55 % white |
| Expanded timer digits | 42 light |
| Progress times | 11 medium, 55 % white |
| Timer chips | 12 semibold |

## Colour

Dark-mode system colours, since the surface is always black.

| Role | Colour |
|---|---|
| Timer | systemOrange `#FF9F0A` |
| Call, charging, camera | systemGreen `#30D158` |
| Microphone (non-call apps) | systemOrange `#FF9F0A` |
| Low battery | systemRed `#FF453A` |
| Charging in Low Power Mode | systemYellow `#FFD60A` |
| AirDrop | systemBlue `#0A84FF` |
| Now Playing bars | average colour of the album art, lifted so it reads on black; white for grey art |
| Secondary button fill | 18 % white |

## Motion

| Moment | Animation |
|---|---|
| Compact / idle | spring, response 0.42, damping 0.76 |
| Alert | spring, response 0.44, damping 0.74 |
| Open (expanded, Home and panels, drop) | spring, response 0.48, damping 0.8 |
| Hover swell / notch appearing on another display | spring, response 0.34, damping 0.72 |
| Hide | spring, response 0.36, damping 0.92 (settles without a bounce) |
| Settings slider changes | spring, response 0.3, critically damped |
| Hover lift | spring, response 0.3, damping 0.68 |
| Content swap | old: fade + blur 4 + scale 0.97 out in 0.12 s; new: fade + blur 6 + scale 0.92 → 1 in a 0.34 s smooth curve after 0.06 s. Both scale from the top edge, so content grows out of the notch |
| Liquid pulse (bubble split) | strength 0 → 1 in 0.08 s, back to 0 over 0.6 s |
| Now Playing bars | 4 capsules, Core Animation keyframe loops of 1.2–1.9 s; resting height 28 % when paused |
| Timer done | bell swings ±16° |

Reduce Motion replaces springs with a 0.2 s ease and turns the liquid effect off.

## Sound and haptics

* Trackpad haptic on expand, on swapping activities and on a successful drop (not on hover).
* Timer done: the system "Glass" sound every 2 s for up to 30 s or until stopped. Can be
  turned off.

## Copy

Short, sentence case, no exclamation marks: "Charging", "Low Battery", "Connected", "Timer",
"Done", "Drop to AirDrop", "Release to AirDrop", "On Call", "Using Microphone".
Times read like the Clock app: `4:59`, `1:02:03`; track time left reads `-3:01`.
