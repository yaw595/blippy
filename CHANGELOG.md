# Changelog

All notable changes to Blippy are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - First public release

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
