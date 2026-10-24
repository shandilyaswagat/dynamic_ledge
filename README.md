<p align="center">
  <img src="Support/AppIcon-1024.png" width="128" alt="Dynamic Notch icon">
</p>

<h1 align="center">Dynamic Notch</h1>

<p align="center">
  The iPhone's Dynamic Island, but for your MacBook's notch.<br>
  <b><a href="https://github.com/shandilyaswagat/dynamic_notch/releases/latest/download/DynamicNotch.dmg">Download it here</a></b> (free, needs macOS 14 or newer)
</p>

---

The notch on my MacBook just sits there doing nothing. I wanted it to work like the island on
my phone, so I made this.

When something's going on, the notch stretches out and shows it. When nothing is, it tucks back in
and you forget it's there.

Here's what it shows:

- Whatever music is playing, from any app, with the album art and play/pause/skip
- Timers, counting down right next to the camera
- Calls on FaceTime, Zoom, Meet, Teams and the rest, with how long you've been on
- Your next calendar event, plus a heads up 5 minutes before it starts
- Volume and brightness when you change them
- A heads up when you plug in your charger or your battery gets low
- Your AirPods or headphones connecting

And when you click it, you get a little home base right under the notch:

- **Home** with your music, next event, quick timers, a Focus timer and your favourite Shortcuts.
  Tap the timer for any length, Pomodoro or a stopwatch, and tap your next event to see the month
- **Tray**, a handy spot to drop files you'll need again in a minute. Drag files onto the notch
  to put them there, and drag them back out when you're ready
- **Clipboard**, the last few things you copied. Click one to copy it again. Passwords are
  skipped and nothing is saved
- **Notes**, a little scratchpad for phone numbers, to-dos, whatever
- **Mirror**, a quick look at your camera before you hop on a call

Drag files onto the notch and you can also AirDrop them straight from there.

Everything else lives behind the grid button at the top right: the timer, stopwatch, calendar,
today's reminders, a scratchpad, your camera mirror and Keep Awake (stops your Mac from
sleeping). Each one has a shortcut too, like ⌃⌥R for the timer.

A few more handy bits: a mute button for your mic during calls, and (if you switch it on in
Settings) a heads-up when a download finishes.

Got a second screen? It stays on your MacBook, or turn on Follow the pointer in Settings and it
follows you there as a floating island.

You can make it small, medium or large, whatever looks right on your screen.

It doesn't need an account and doesn't track anything. The only time it goes online is a quick
daily check for a new version, which you can turn off in Settings. All of this is free.

## Installing it

**The easy way, if you use [Homebrew](https://brew.sh):**

```bash
brew install --cask shandilyaswagat/tap/dynamic-notch
```

That's it, no extra steps. Otherwise, download it yourself:

Heads up: I haven't paid Apple for a developer account yet, so the first time you open the app
your Mac will grumble about it. You only have to deal with this once and it takes about a minute.

1. Download [DynamicNotch.dmg](https://github.com/shandilyaswagat/dynamic_notch/releases/latest/download/DynamicNotch.dmg) and open it.
2. Drag **Dynamic Notch** into your **Applications** folder.
3. Go to Applications and double-click **Dynamic Notch**. Your Mac will say it couldn't open it.
   Just hit **Done**.
4. Open **System Settings**, go to **Privacy & Security** and scroll down a bit. You'll see a line
   saying Dynamic Notch was blocked. Click **Open Anyway**, type your password (or use Touch ID)
   and click **Open Anyway** one more time.
5. That's it. The notch will say hi to you by name with a little wave, and a capsule icon shows
   up in your menu bar.

If you're comfortable with Terminal, you can skip steps 3 and 4. After dragging the app into
Applications, run this and then open the app like normal:

```bash
xattr -dr com.apple.quarantine "/Applications/Dynamic Notch.app"
```

## Using it

| If you want to | Do this |
|---|---|
| Open Home, Tray, Clipboard, Notes or Mirror | Click the notch, then pick a tab at the top |
| Start a timer, a focus session or a shortcut | Click the notch, then tap it on Home |
| See more about something | Click it |
| Close it | Click anywhere else, or just move your mouse away (Notes stays open until you click away or press Escape) |
| Skip a song | Swipe left or right on the music with two fingers |
| Open or close it without clicking | Choose **Hover** in Settings › General, or pull down on the notch with two fingers; push up to close |
| Get back to Home | Click the back arrow at the top left |
| Keep files for later, or AirDrop them | Drag them onto the notch and drop on **Tray** or **AirDrop** |
| Pause a timer, skip a song, open settings | Right-click the notch |
| Change the size, pick your Shortcuts, turn stuff off | Click the capsule icon in the menu bar, then **Settings…** |

You'll probably want to switch on **Open at login** in Settings so it's always running.

## Things people ask

**I installed it and nothing's showing up.** That's on purpose. It stays hidden until there's
something to show, like music or a timer. Hover over the notch and it'll puff out a little. Click
it to open it.

**My Mac doesn't have a notch.** It still works. You'll get a small fake notch at the top of the
screen whenever there's something to show.

**My music isn't showing.** Play something and give it a second. The app uses a hidden bit of
macOS to see what's playing. If Apple ever removes that in an update, music will stop showing up
but everything else will keep working.

**Is it safe?** All the code is right here in this repo, so anyone can look through it. The app
doesn't collect anything, and the only time it goes online is to check GitHub for a new version. That warning during install only shows up because
I haven't registered the app with Apple yet. I'm planning to do that later.

**Why is it asking for my camera or calendar?** Only if you use those bits. It asks for the camera
the first time you open Mirror, and for your calendar when you click Connect. Nothing gets
recorded or sent anywhere. Say no and everything else keeps working.

**Does it keep what I copy?** Only while the app is running, and only the last 20 bits of text.
It's never written to disk, and anything a password manager marks as private is skipped. Don't
want it at all? Turn off Clipboard in Settings and it stops watching right away.

**How do I update it?** It updates itself. When a new version is out, the notch lets you know;
click it, or go to Settings › About, and hit **Install and Relaunch**. With Homebrew,
`brew upgrade` works too. Prefer doing it by hand? Download the new version and drag it into
Applications again. Replace the old one when it asks. Your settings stay put.

**How do I get rid of it?** Click the capsule icon in the menu bar and pick **Quit Dynamic Notch**,
then drag the app from Applications to the Trash. If you want to clear out everything it saved too,
delete `~/Library/Application Support/Dynamic Notch` and
`~/Library/Preferences/com.rectircle.DynamicNotch.plist`.

## What you need

- macOS 14 (Sonoma) or newer
- Works on Apple silicon and Intel Macs, but it's really made for MacBooks with a notch

## What's new

Check the [changelog](CHANGELOG.md) to see what changed in each version.

## Want to build it yourself?

Build steps and notes on how it all fits together are in the [docs folder](docs/README.md).
