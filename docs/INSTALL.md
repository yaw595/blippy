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

- **Wi-Fi:** keep the phone and Mac on the same Wi-Fi. To send to the phone, open **Quick Share** and tap
  **Receive** (and set visibility to **Everyone**). To send to the Mac, share a file and pick your Mac.
- **Cable:** turn on **USB debugging** (Settings → About phone → tap *Build number* 7 times →
  Settings → System → Developer options → *USB debugging*), plug in the cable, and tap **Allow** on the phone.

Stuck? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
