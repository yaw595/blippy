# Third-party notices

Blippy is licensed under the Apache License 2.0 (see `LICENSE`). It includes or links the
following third-party software. Full license texts are in the `LICENSES/` folder.

| Component | What it is used for | License | Copyright |
|---|---|---|---|
| [NearDrop](https://github.com/grishka/NearDrop) | The Quick Share protocol implementation Blippy is based on | Unlicense (public domain) | Grishka |
| [swift-protobuf](https://github.com/apple/swift-protobuf) | Protocol Buffers runtime | Apache 2.0 | Apple Inc. and the Swift project authors |
| [SwiftECC](https://github.com/leif-ibsen/SwiftECC) | Elliptic-curve cryptography for the Quick Share handshake | MIT | Leif Ibsen |
| [BigInt](https://github.com/leif-ibsen/BigInt) | Big-integer math used by SwiftECC | MIT | Leif Ibsen |
| [ASN1](https://github.com/leif-ibsen/ASN1) | ASN.1 encoding used by SwiftECC | MIT | Leif Ibsen |
| Android Debug Bridge (`adb`), from the Android SDK Platform-Tools | Sends files to the phone over a USB cable | Apache 2.0 (components listed in `Vendor/adb-NOTICE.txt`) | The Android Open Source Project / Google LLC |

The generated protocol-buffer sources in `NearbyShare/Protobuf` are produced by the
swift-protobuf code generator from the `.proto` files in `NearbyShare/ProtobufSource`.

## Trademarks

Android, Quick Share and Pixel are trademarks of Google LLC. macOS, Finder and SF Symbols are
trademarks or property of Apple Inc. Blippy is an independent project and is not affiliated
with, endorsed by or sponsored by Google or Apple.
