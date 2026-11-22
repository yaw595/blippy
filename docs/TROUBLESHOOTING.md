# Troubleshooting

## My phone doesn’t show up (Wi-Fi)

- On the phone, open **Quick Share** and tap **Receive**, and set visibility to **Everyone** (on Samsung: **Who can share
  with you → Anyone nearby**, which turns itself off after 10 minutes). Keep that screen open and the phone unlocked.
- **Turn off auto-lock** while you send (Settings → Display → Screen timeout). Phones stop advertising once the screen
  locks, and Samsung is strict about this.
- Blippy says **“N phones are nearby but hidden”** when it can see a phone on the network that isn't showing its name:
  Quick Share is closed, or visibility is set to Contacts only. Open Quick Share on it and choose Everyone, **scan the
  QR code** Blippy shows after about 25 seconds, or use the cable.
- Put both devices on the **same Wi-Fi network**. Some routers have “client isolation” or a guest
  network that blocks devices from seeing each other; turn that off.
- Check **System Settings → Privacy & Security → Local Network** and make sure **Blippy** is on.
- If a VPN or firewall is running on the Mac, try pausing it.
- The first search can take a few seconds. After 25 seconds Blippy shows the QR code and a help button.

## Transfers stay on “Connecting…” or fail

- Close and reopen the phone's Quick Share screen to get a fresh connection, then try again.
- Make sure the phone's screen is on and unlocked.

## I don’t get a notification to accept a file

Turn notifications on in **System Settings → Notifications → Blippy**, and set the style to **Alerts**.
You can also accept on Blippy’s **Receive** page. Check that no Focus mode is hiding notifications.

## “Blippy can’t be opened” / “Apple cannot check it for malicious software”

See [INSTALL.md](INSTALL.md#2-open-it-the-first-time).

## Blippy isn’t in the Finder Share menu

Enable it in **System Settings → General → Login Items & Extensions → Sharing**. If it is missing, open
Blippy once and wait a few seconds, then check again.

## Cable: “Set USB to File transfer”

The easiest way: unlock the phone, swipe down, tap **Charging this device via USB** and choose **File transfer**.
No developer mode is needed. Use a cable that carries data (not a charge-only cable), and keep the phone unlocked
while sending; turn off auto-lock if the screen locks quickly.

## Cable: using USB debugging instead (a little faster)

You first need to turn on developer mode: Settings → About phone → tap **Build number** 7 times (Samsung: About phone →
Software information → Build number). Then Settings → System → **Developer options** (Samsung: Settings → Developer
options) → **USB debugging**.

## Cable: “Couldn’t open the phone” (File transfer)

macOS's camera service sometimes holds a phone that is in File transfer mode. Unplug the cable, plug it back in, and
try again. Close Android File Transfer, Image Capture or Photos if they are open.

## Cable: “Allow on your phone”

Unlock the phone and tap **Allow** on the “Allow USB debugging?” prompt. Tick “Always allow from this
computer” so it asks only once. If the prompt never appears, unplug and replug the cable, or in
Developer options choose **Revoke USB debugging authorizations** and try again.

## Cable: the phone isn’t detected

- Try another cable or port, and set the phone’s USB mode to **File transfer** (or **Photo transfer** for photos and videos only).
- Unlock the phone. A locked phone shows no storage, so nothing can be sent.
- If you also use Android Studio or `adb` yourself, it shares the same `adb` server. Run `adb kill-server` and try again.

## Still stuck?

[Open an issue](https://github.com/yaw595/blippy/issues) and include your macOS version, your phone model and
Android version, and what you saw. Don’t include private file names.
