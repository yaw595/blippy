# Privacy

**Blippy collects no data.** There is no telemetry, no analytics, no crash reporting, no
accounts and no server. Nothing about you, your devices or your files is sent to the
developers or to anyone else.

## What Blippy does on your network

- **Wi-Fi transfers** go directly between your Mac and your phone on your local network, using
  the Quick Share protocol. They are encrypted end to end between the two devices.
- **Cable transfers** go over USB, either with Android Debug Bridge (`adb`) or with Blippy's own MTP helper
  (`blippy-mtp`), both run on your Mac. They talk to your phone over the cable only; nothing goes to the internet.
- Blippy makes **no connections to the internet**. The only web addresses it knows are links you
  choose to open (the GitHub page or the optional support page), which open in your browser.

## What Blippy stores

- **Transfer history** (file names, device names, dates, sizes) is saved on your Mac in
  `~/Library/Application Support/Blippy/history.json`. You can remove entries from the History
  page, or delete the file.
- **Settings** (sounds on/off, last device used) are saved in your standard macOS preferences.
- Received files are saved to your **Downloads** folder.

## Permissions Blippy asks macOS for

- **Local network:** to find your phone and receive files on your Wi-Fi.
- **Notifications:** to ask you to accept an incoming transfer.
- **Files and folders:** only the ones you pick or drop into the app.

If you find a privacy problem, please report it (see `SECURITY.md`).
