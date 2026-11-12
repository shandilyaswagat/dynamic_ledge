# Working on Dynamic Ledge

Dynamic Ledge is a free, open-source (GPL-3.0) macOS app that turns the MacBook notch into a
Dynamic Island. Swagat Shandilya owns the product and decides what goes in. Read this whole file
before changing anything, and follow it on every task.

## Before you write code
- Read `README.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md` and `CHANGELOG.md` first. Match what
  is already there instead of inventing new patterns.
- Build only what the task asks for. If you think something else is needed, say so and stop; do
  not add it.
- A new feature needs Swagat's yes before it's built. Fixes to existing behaviour don't.

## Local QA installation
- Install development builds only as `/Applications/QA.app`. Never replace, rename, or remove
  the original `/Applications/Dynamic Ledge.app` when building or installing QA.

## Things that were decided and must not come back
- No weather, online artwork, second lyrics source, Focus alerts or Focus indicator, AirPods
  battery readouts, notifications from other apps, or a search bar in the notch.
- No system stats beyond the existing Stats tile, colour picker, terminal, water tracker or
  bookmarks.
- Clipboard history is text only, the last 20 items, kept in memory only, never on disk.
- Nothing about the user is collected. The app goes online only for update checks (GitHub),
  lyrics (lrclib.net, song name only) and one anonymous daily TelemetryDeck count. Any other
  network call needs Swagat's approval first.
- Never ask for, store or send API keys, passwords or tokens. Never open another app's sign-in or
  credentials files. If something must be secret, it goes in the macOS Keychain, never in
  UserDefaults.
- New features that read the user's files or run other programs are off by default, and the
  Settings text says plainly what they read.
- Ask for a permission (Camera, Calendar, Accessibility…) only when the feature that needs it is
  first used.
- No dependencies: SwiftUI views in an AppKit shell, Swift Package Manager, nothing from outside.

## Never change
- Bundle id `com.rectircle.DynamicNotch`, and the release asset names `DynamicNotch.dmg`.
- The signing setup (the "Dynamic Ledge" certificate), `Scripts/release.sh`, the update signing
  key, and the update verification in `Updater.swift`.
- `VERSION`. Swagat picks version numbers and releases.

## How code should look
- Match the surrounding code: same naming, same short doc comments, same structure. No large
  rewrites of files you weren't asked to touch.
- Debug-only helpers (test hooks, DistributedNotification listeners) go inside `#if DEBUG`.
- Settings follows macOS System Settings: native sidebar with search, back/forward and the page
  title in the toolbar, grouped Forms, coloured tiles with white symbols in pages. The sidebar
  keeps the original icons (gearshape, capsule, house, square.stack.3d.up). Don't restyle it.
- Notch sizes and colours live in `IslandMetrics.swift` and `docs/DESIGN.md`; update both together.
- Settings text is short, plain, sentence case, no exclamation marks, and says what happens.

## Before you commit
1. Run `./Scripts/check.sh`. Every test must pass and the release build must have no warnings.
2. Add tests for new behaviour, and update tests you change on purpose.
3. Add changes to `CHANGELOG.md` under `## [Unreleased]` only, never under a released version,
   written for users in the same style as the existing entries.
4. Update `README.md` and `docs/` when behaviour or design changes.
5. Commit to `feature/next` only. Never push to `main` or `develop`, never force-push, never tag
   or publish a release.
6. Commit messages: a short summary line, then what changed and why. Do not mention AI tools,
   and add no "Co-Authored-By" or "Generated with" lines.
7. In your final message, list anything you weren't sure about instead of guessing.
