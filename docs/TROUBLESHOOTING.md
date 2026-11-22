# Troubleshooting

## My phone doesn’t show up (Wi-Fi)

- On the phone, open **Quick Share** and tap **Receive**, and set visibility to **Everyone**. Keep the screen on.
- Put both devices on the **same Wi-Fi network**. Some routers have “client isolation” or a guest
  network that blocks devices from seeing each other; turn that off.
- Check **System Settings → Privacy & Security → Local Network** and make sure **Blippy** is on.
- If a VPN or firewall is running on the Mac, try pausing it.
- The first search can take a few seconds. Blippy suggests “Same Wi-Fi? Phone on Receive?” after 15 seconds.

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

## Cable: “Turn on USB debugging”

Settings → About phone → tap **Build number** 7 times → Settings → System → **Developer options** →
**USB debugging**. Use a cable that carries data (not a charge-only cable).

## Cable: “Allow on your phone”

Unlock the phone and tap **Allow** on the “Allow USB debugging?” prompt. Tick “Always allow from this
computer” so it asks only once. If the prompt never appears, unplug and replug the cable, or in
Developer options choose **Revoke USB debugging authorizations** and try again.

## Cable: the phone isn’t detected

- Try another cable or port, and set the phone’s USB mode to **File transfer**.
- If you also use Android Studio or `adb` yourself, it shares the same `adb` server. Run `adb kill-server` and try again.

## Still stuck?

[Open an issue](https://github.com/yaw595/blippy/issues) and include your macOS version, your phone model and
Android version, and what you saw. Don’t include private file names.
