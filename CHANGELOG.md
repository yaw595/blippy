# Changelog

All notable changes to Blippy are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-22

### Added
- Cable transfer over **MTP** ("File transfer" USB mode, new and not yet widely tested): no developer mode or USB debugging needed, any file type, verified size, folders zipped first. Built on libusb in a small helper, `blippy-mtp`.
- The Send page tells you when phones are on the network but **hidden**, opens a QR code after about 25 seconds with no phone, and offers the Cable page and a "Can't see your phone?" help sheet.
- Step-by-step setup in the app and docs: developer mode and USB debugging, File transfer mode, Quick Share visibility (Everyone / Anyone nearby), and turning off auto-lock.

### Fixed
- The sidebar no longer shifts when a page is taller than the window.
- Blippy no longer rejects the 17-byte advertisement that some Samsung phones send when hidden.

## [0.1.0] - First public release

### Changed
- The Xcode project, target, scheme, source folder, module and code identifiers are now named Blippy (they used the old NearDrop names). NearDrop is still credited as the project Blippy grew out of.
- The README now explains how Blippy works: discovery, the encrypted handshake and PIN, chunked sending, the cable path, what is stored and the limits.

### Fixed
- A phone that opens Quick Share *after* Blippy is already searching is now found. Blippy reacts when a phone adds its details a moment after announcing itself, and searches again every few seconds while nothing is found.

### Added
- Send and receive files between a Mac and an Android phone over Wi-Fi with Quick Share.
- Send to several phones at once, with per-device progress and time remaining.
- Cable transfer over USB with `adb`: saves to Downloads on the phone and verifies each file.
- Finder Share menu entry, drag and drop onto the window, menu-bar icon and a global shortcut (⌃⌥N).
- Folders are zipped automatically before sending.
- History and Devices pages; remove a history item, or delete a received file for good.
- File previews, completion sounds, notifications and Dock badge for incoming transfers.
- A full Mac menu bar, About window, privacy statement and open-source license viewer.
- Appearance setting: follow your Mac, or always Light or Dark.
- Polish: one consistent card style, filled sidebar icons, soft page fades, smoothly rolling numbers, a pop when a send finishes, buttons that press in, and trackpad haptics.
- Apache 2.0 license. No telemetry, no accounts, no servers.
