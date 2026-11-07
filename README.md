# 🧽 LockitClean

A tiny macOS app that locks your keyboard and trackpad so you can wipe your Mac clean without typing gibberish or clicking random things.

## How it works

1. Pick how long you need (30 sec – 5 min) and hit **Lock & Clean**.
2. The screen goes dark and **all keyboard, trackpad, mouse and media-key input is blocked**.
3. Wipe away.
4. Unlock by **holding both ⌘ keys for 2 seconds**, or just wait for the timer to finish.

The timer is a safety net. The app always unlocks when it runs out, so you can't get stuck.

## Download

Grab **LockitClean.dmg** from the [Releases](../../releases) page, open it, and drag LockitClean into Applications.

> The app isn't notarized by Apple, so the first time you open it, **right-click → Open**, then confirm.

## Build from source

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh            # builds build/LockitClean.app + build/LockitClean.dmg
./build.sh install    # same, and installs it into /Applications
```

The first time you press **Lock & Clean**, macOS will ask for **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). Turn on LockitClean and press the button again.

> After rebuilding, macOS may treat it as a new app. If locking stops working, remove LockitClean
> from the Accessibility list and add it again.

## Under the hood

- **`CGEventTap`** at the HID level catches every input event before the system sees it and drops it.
- The tap still *reads* modifier changes, which is how the both-⌘ unlock combo is detected
  (using the left/right device-specific modifier bits).
- Borderless windows at `.screenSaver` level cover every display, and
  `NSApplication.presentationOptions` hides the Dock and menu bar and disables app switching and Force Quit while locked.
- Written in Swift with AppKit, as a single file. No dependencies.

## Limitations

- The power / Touch ID button is handled by hardware and can't be blocked. Avoid pressing it while wiping.
- Pressing both ⌘ keys for 2 full seconds with a wipe is possible but unlikely.

## License

MIT © Ayaz Ata Türkmen
