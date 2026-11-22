# Publishing Blippy on GitHub (maintainer guide)

A checklist for the first release and for every release after it.

## One-time setup

### 1. Your identity (forks only)

This repository is already set up for its maintainer (GitHub `yaw595`, bundle ID `io.github.yaw595.Blippy`). If you
fork Blippy to publish your own build, replace that identity first, and **do it before building a release**, so
your app doesn't share an ID with the original:

```bash
scripts/set-identity.sh --github YOUR_USERNAME --coffee https://example.com/your-support-link
```

It updates the GitHub name and support link in the app and the docs, and the bundle identifier
(`io.github.<username>.Blippy`, with `.ShareExtension` for the Finder extension). Leave out `--coffee` to hide the
support section in the app.

### 2. A clean repository

If you start from a copy of the folder, remove any old `.git` folder and start your own history:

```bash
rm -rf .git
git init -b main
git add .
git status          # check that build/, dist/ and Vendor/adb are NOT listed
git commit -m "Initial commit"
```

### 3. Create the GitHub repository

1. On github.com choose **New repository**. Name it `blippy` (to match the links in the docs), leave it
   empty (no README, license or .gitignore), and make it **Public**.
2. Push:

   ```bash
   git remote add origin https://github.com/YOUR_USERNAME/blippy.git
   git push -u origin main
   ```

3. In **Settings → General** add a description ("Send files between your Mac and Android phone. Free,
   open source, no data collected.") and **Topics**: `macos`, `android`, `quick-share`, `file-transfer`,
   `swiftui`, `adb`.
4. GitHub detects the Apache 2.0 license from `LICENSE` and shows it on the repo page.
5. **Settings → General → Features**: keep **Issues** on; turn on **Discussions** if you want a Q&A space.
6. **Settings → Code security**: turn on **Private vulnerability reporting** (the link in `SECURITY.md` needs it).
7. Optional: **Settings → General → Sponsorships** shows the Buy Me a Coffee button (from `.github/FUNDING.yml`).
8. Screenshots are already in `docs/images/` and shown in the README (Send, Receive, Cable, Devices, Settings).
   They were taken with the app in full screen in Light mode. To retake or add one (for example a phone found,
   a transfer in progress, or History), press **⇧⌘4**, then **Space**, then click the window, save it into
   `docs/images/`, and add an `<img>` line next to the others in the README. History was left out on purpose
   because it shows real file names; clear it first if you want to include it.
9. Add your screen recording: drag the video file into a GitHub issue comment box (you don't need to submit it) or
   into the description of a release draft. GitHub uploads it and shows a `https://github.com/user-attachments/...`
   link. Paste that link on its own line in the README where the demo comment is, and it plays inline.

## Every release

### 1. Version and changelog

- Edit `MARKETING_VERSION` in `Blippy.xcodeproj/project.pbxproj` (or in Xcode: target → General → Version)
  and bump `CURRENT_PROJECT_VERSION`.
- Move the notes in `CHANGELOG.md` under a new version heading.

### 2. Build the DMG

```bash
./scripts/fetch-adb.sh      # first time only: downloads Google's adb into Vendor/
./scripts/build-mtp.sh      # first time only: builds the MTP helper (downloads libusb source) into Vendor/
./scripts/build-dmg.sh
```

This produces `dist/Blippy-<version>.dmg` and a `.sha256` file. The build is universal
(Apple Silicon and Intel) and ad-hoc signed.

**Test the DMG on a Mac that did not build it** if you can (a friend's Mac, or a fresh user account):
open the DMG, drag to Applications, do the first-open steps from `docs/INSTALL.md`, and send a file.

### 2. Tag and publish

```bash
git tag -a v0.1.0 -m "Blippy 0.1.0"
git push origin v0.1.0
```

On GitHub: **Releases → Draft a new release**, choose the tag, and:

- Title: `Blippy 0.1.0`
- Description: paste the changelog section, then add the install note and checksum:

  > **Install:** open the DMG, drag Blippy to Applications. The first time, macOS asks you to confirm:
  > System Settings → Privacy & Security → **Open Anyway**. [Details](docs/INSTALL.md)
  >
  > SHA-256: `<paste the contents of the .sha256 file>`

- Attach **both** `Blippy-0.1.0.dmg` and `Blippy-0.1.0.dmg.sha256`.
- Tick **Set as the latest release** (and **pre-release** for early betas), then **Publish**.

The "Download for Mac" link in the README points to `/releases/latest`, so it always finds the newest DMG.

## About signing (why people see a warning)

Blippy is signed with a free **ad-hoc** signature. That is enough to run on Apple Silicon, but macOS shows
an "unidentified developer" warning the first time, which is why the install guide has the **Open Anyway**
steps. To remove the warning you need Apple's paid developer program (US$99 per year):

1. Join the Apple Developer Program and create a **Developer ID Application** certificate in Xcode
   (Settings → Accounts → Manage Certificates).
2. Build with it: `SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-dmg.sh`.
3. **Notarize** the DMG so Gatekeeper trusts it:

   ```bash
   xcrun notarytool store-credentials blippy-notary      # one time: Apple ID, team ID, app-specific password
   xcrun notarytool submit dist/Blippy-0.1.0.dmg --keychain-profile blippy-notary --wait
   xcrun stapler staple dist/Blippy-0.1.0.dmg
   ```

   (Developer ID signing also needs the hardened runtime and signing the bundled `adb` with the same identity;
   adjust the "Bundle adb" build phase to use `$EXPANDED_CODE_SIGN_IDENTITY` and `--options runtime`.)

Until then, the ad-hoc build is fine for an open-source project.

## Good to know

- **`Vendor/blippy-mtp` is not committed** either: `scripts/build-mtp.sh` builds it (universal, libusb linked statically,
  LGPL-2.1: keep `Helper/blippy-mtp.c` and the license text with the app, which the build already does).
- **`adb` is not committed** (it is 15 MB and Google's). `scripts/fetch-adb.sh` downloads it, and the build
  fails with a clear message if it is missing. The released app includes it, and the licenses are in the app
  under **Help → Open Source Licenses**.
- **Android and Quick Share are trademarks of Google.** Keep the disclaimer in the README and avoid using
  Google's logos.
- **NearDrop's author asked** (in their repository) that AI-assisted contributions not be sent to their project.
  Blippy is a separate, openly licensed fork, but it is a courtesy to credit them (already done in the README,
  NOTICE and About window) and not to send Blippy's changes upstream.
- **Homebrew cask** (later): once you have a few releases, a cask makes installs a one-liner
  (`brew install --cask blippy`) by pointing at your release DMG and its SHA-256.
