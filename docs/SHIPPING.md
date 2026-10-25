# Shipping

Dynamic Notch is distributed as a DMG on GitHub Releases, outside the Mac App Store (the Now
Playing helper uses a private macOS framework, which App Review does not allow).

There are two stages:

| | Now: unsigned | Later: signed and notarized |
|---|---|---|
| Cost | Free | Apple Developer Program, $99 a year |
| What users see on first open | "Not Opened" warning, then **Open Anyway** in Privacy & Security | One normal "downloaded from the internet" prompt |
| What changes in the README | Install steps 3–4 and the Terminal option | Remove those steps and the note above them |

Release assets are always named `DynamicNotch.dmg`, so the README's link
`releases/latest/download/DynamicNotch.dmg` always points to the newest version.

## Versions and the changelog

* The version lives in the `VERSION` file. It follows semantic versioning: bump the last number
  for fixes (1.1.0 → 1.1.1), the middle one for new features (1.1.1 → 1.2.0), the first one for
  big changes that break how people use the app.
* The build number is the commit count, so it always goes up on its own.
* Every release gets a section in [CHANGELOG.md](../CHANGELOG.md), written for users. The release
  script copies that section into the GitHub release notes, so write it the way you'd want people
  to read it.

## Branches

* **develop** is where all work happens. Commit features and fixes here.
* **main** only ever holds released code. Every commit on main is something users can download.

When develop is ready to ship:

```bash
git switch develop && git pull
```

```bash
git switch main && git pull && git merge --no-ff develop
```

Then follow the release steps below on main, and afterwards bring develop up to date so it
has the version bump and changelog:

```bash
git switch develop && git merge main && git push
```

## Update signing (required before publishing)

Updates are authenticated with Ed25519 independently of Apple's code signing. The updater
rejects missing signatures, a different key, altered image bytes, incorrect product/version,
and size/hash mismatches before mounting the image. Old checksum-only releases cannot be
installed by this updater. An empty public-key file disables in-app installation safely.

Generate the production key on a protected signing machine, outside this repository:

```bash
swift Scripts/sign-update.swift generate /secure/location/dynamic-notch-update.key
```

The command creates a private key with mode 0600 and prints only the public key. Put that public
key in `Support/UpdatePublicKey.txt` and commit the public file. Back up the private key securely;
never commit it, upload it as a release asset, or store it beside releases. Restrict CI signing
secrets with approval controls independent of the GitHub release account. Do not regenerate keys
for each release: existing installations pin the public key shipped in their app.

Set `UPDATE_SIGNING_KEY_FILE=/secure/location/dynamic-notch-update.key` when running
`Scripts/release.sh`. After building the final DMG (including notarization/stapling), the script
signs a manifest and publishes `DynamicNotch.update.json` alongside the image.
The packaging script writes `build/ReleaseInfo.plist` from the exact staged app before removing
staging; release signing validates this file, rather than an older standalone app bundle. Signing verifies
that the built app embeds the matching public key and has the expected version and bundle ID.
The manifest envelope holds base64 payload bytes and their signature; the signed payload contains
the version, bundle ID, DMG filename, byte length and SHA-256.

The updater validates the extracted bundle ID and version. If the current app has an Apple
signing Team ID, updates must also pass strict code validation for that same Apple-trusted team
and identifier. Ad-hoc builds rely on the pinned release-signing key. Quarantine is not stripped
by the installer; normal macOS launch checks still apply.

The first release with this protection must reach users through a trusted installation channel.
Old installed versions do not gain signature verification until replaced. For Dynamic Notch the
key ships from 1.3.0 on. 1.2.0 still updates in place using the published `.sha256` file, so keep
uploading it. From 1.3.0 on, every update installs from Settings › About only after passing the
signature check. A build without a usable public key (for example a local build made before the
key existed) labels its update button **Download** and opens the release page instead; those
copies need one manual download. Plan key rotation by
shipping a trusted update with the next public key before retiring the old signing key.

## Making a release now (ad-hoc Apple signature)

1. On main, change `VERSION`, add the matching `## [x.y.z] - date` section to `CHANGELOG.md`,
   and commit.
2. Run the manual checklist in [QA.md](QA.md) on a build of that commit.
3. Run:

   ```bash
   UPDATE_SIGNING_KEY_FILE=/secure/location/dynamic-notch-update.key ./Scripts/release.sh
   ```

The script stops if you're not on main, local main doesn't match GitHub, the working tree isn't
committed, the tag already exists, or the changelog has no section for the version. Then it runs all checks, builds `build/DynamicNotch.dmg`, tags
`vX.Y.Z`, pushes, and publishes the GitHub release with the changelog section as its notes (plus
short install steps for new users). It also uploads `DynamicNotch.dmg.sha256`, for manual checksum checks, plus the signed manifest the in-app
updater requires before installing, and points the Homebrew cask in `shandilyaswagat/homebrew-tap`
at the new version (`Scripts/update-cask.sh`, from `packaging/homebrew/`).

### Why downloaded copies still get Now Playing

Everything inside a downloaded app carries macOS's quarantine flag. Opening the app with **Open
Anyway** approves the app, but the Now Playing helper is loaded by `/usr/bin/perl`, which would
trigger a second, separate warning for the library and fail. So on launch the app writes its own
copy of the helper to `~/Library/Application Support/Dynamic Notch/` (a copy the app writes has no
quarantine flag and keeps the library's signature) and loads that.

## Moving to signed and notarized releases

### What you need once

1. **Apple Developer Program** membership.
2. A **Developer ID Application** certificate in your login keychain: Xcode › Settings ›
   Accounts › Manage Certificates › + › Developer ID Application. An *Apple Development*
   certificate is not enough: Gatekeeper rejects it on other Macs and it can't be notarized.
3. A notarization profile stored in the keychain:

   ```bash
   xcrun notarytool store-credentials dynamic-notch --apple-id you@example.com --team-id TEAMID
   ```

   It asks for an app-specific password (appleid.apple.com › Sign-In and Security).
4. Optional: change the bundle id (`BUNDLE_ID`, default `com.rectircle.DynamicNotch`).

### Release steps

Same as above, with your identity and notarization profile set:

```bash
UPDATE_SIGNING_KEY_FILE=/secure/location/dynamic-notch-update.key SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=dynamic-notch ./Scripts/release.sh
```

`make-dmg.sh` then signs the helper library and the app with hardened runtime, the camera and
calendar entitlements and a secure timestamp, notarizes the DMG, staples the ticket and runs a
Gatekeeper check. After the first signed release, simplify the README's install section and
the install note the release script adds.

## Not included yet

* **Crash reporting.** None. Network access is used for update checks and downloads.
