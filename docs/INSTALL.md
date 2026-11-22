# Installing Blippy

## 1. Install

1. Download the latest `Blippy-x.y.z.dmg` from the [Releases page](https://github.com/yaw595/blippy/releases/latest).
2. Open the DMG and drag **Blippy** into **Applications**.
3. Eject the disk image.

## 2. Open it the first time

Blippy is free software and is **not** signed with a paid Apple Developer ID certificate, so macOS shows
a warning the first time (“Blippy can’t be opened because Apple cannot check it for malicious software”).
This is expected. Pick one of these once; after that it opens normally.

**macOS 15 (Sequoia) or later — System Settings**

1. Try to open Blippy from Applications and click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security**, click **Open Anyway** next to “Blippy was blocked”, and confirm.

**macOS 14 (Sonoma)**

Right-click (or Control-click) Blippy in Applications, choose **Open**, then **Open** again.

**Terminal (any version)**

```bash
xattr -dr com.apple.quarantine /Applications/Blippy.app
```

> You can check what you are opening: the release page lists a SHA-256 checksum for the DMG
> (`shasum -a 256 Blippy-x.y.z.dmg`), and the whole source is in this repository.

## 3. Allow what Blippy needs

macOS will ask for two permissions the first time. Both are needed:

- **Notifications:** so you can accept incoming files.
- **Local Network:** so Blippy can find your phone on Wi-Fi.

If you clicked “Don’t Allow”, turn them back on in **System Settings → Notifications** and
**System Settings → Privacy & Security → Local Network**.

## 4. Optional: the Finder Share menu

Blippy registers a **Share** entry for Finder. If it does not appear, turn it on in
**System Settings → General → Login Items & Extensions → Sharing** (or **Extensions → Sharing**),
and tick **Blippy**.

## 5. On your phone

- **Wi-Fi:** keep the phone and Mac on the same Wi-Fi. To send to the phone, open **Quick Share**, set **Who can share
  with you** to **Everyone** (on Samsung: **Anyone nearby**, which only lasts 10 minutes), and keep that screen open and
  the phone unlocked. To send to the Mac, share a file and pick your Mac.
  - **Turn off auto-lock** (or set a long screen timeout) while you send: Settings → Display → Screen timeout. Many
    phones, Samsung especially, stop sharing and pause USB when the screen locks.
  - Blippy can only see a phone that is showing its name. A phone that is hidden is reported as "nearby but hidden";
    the QR code or the cable still work.
- **Cable, option 1: File transfer** (easiest, no developer mode). Plug in a USB cable that carries data, unlock the
  phone, swipe down, tap **Charging this device via USB**, and choose **File transfer**.
- **Cable, option 2: USB debugging** (a little faster). Enable developer mode: Settings → About phone → tap
  *Build number* 7 times (on Samsung: Settings → About phone → Software information → *Build number*). Then open
  Settings → System → Developer options (on Samsung: Settings → Developer options), turn on **USB debugging**, plug in
  the cable, and tap **Allow** on the phone (tick “Always allow”).

Stuck? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
