# Contributing to Blippy

Thanks for helping! Bug reports, fixes, translations, ideas and testing on other phones and Macs are all welcome.

## Ground rules

- **No telemetry, ever.** Pull requests that add analytics, tracking, crash reporting, accounts or any
  network call to a server will be declined. Blippy's promise is that nothing leaves your devices.
- Keep it **small and clean**. Prefer removing code to adding it, and keep the interface calm.
- Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

```bash
git clone https://github.com/yaw595/blippy.git && cd blippy
./scripts/fetch-adb.sh
open Blippy.xcodeproj
```

You need Xcode 26 or later (developed with a recent Xcode beta). To run locally without an Apple developer account, build the **Blippy**
scheme with *Sign to Run Locally*, or from the command line:

```bash
xcodebuild -project Blippy.xcodeproj -scheme Blippy -configuration Debug \
  -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
```

## Where things are

| Path | What |
|---|---|
| `NearbyShare/` | The Quick Share protocol (framework). Based on NearDrop. See `docs/PROTOCOL.md`. |
| `ShareExtension/` | The Finder Share popup, and the UI + send logic shared with the app (`ShareView.swift`, `SendSession.swift`). |
| `Blippy/` | The app: window and pages (`AppWindow.swift`), menu bar (`AppMenu.swift`), cable transfer (`Cable.swift`), history and devices (`History.swift`). |
| `Design/` | The icon generator (`make_icons.swift`) and design assets. |
| `scripts/` | `fetch-adb.sh`, `build-dmg.sh`, `set-identity.sh`. |
| `docs/` | Install and troubleshooting guides, protocol notes. |

## Making a change

1. Open an issue first for anything big, so we can agree on the approach.
2. Branch from `main`, make a focused change, and test it with a real phone if it touches transfers.
3. Update `CHANGELOG.md` for anything users will notice.
4. Open a pull request and fill in the template.

## License

By contributing you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), the same as the project. New source files should start with
`// SPDX-License-Identifier: Apache-2.0`.
