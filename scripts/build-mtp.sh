#!/bin/bash
# Builds Blippy's MTP helper (Helper/blippy-mtp.c) as a universal binary (Apple Silicon + Intel) into
# Vendor/blippy-mtp. It downloads the libusb source (LGPL-2.1) from its official GitHub release and links
# it statically. The result is bundled into the app by the "Bundle adb" build phase.
# Usage: scripts/build-mtp.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ -x Vendor/blippy-mtp ] && [ "${1:-}" != "--force" ] && [ Vendor/blippy-mtp -nt Helper/blippy-mtp.c ]; then
  echo "Vendor/blippy-mtp is up to date. Use --force to rebuild."
  exit 0
fi

VERSION="1.0.29"
URL="https://github.com/libusb/libusb/releases/download/v${VERSION}/libusb-${VERSION}.tar.bz2"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading libusb ${VERSION}:"
echo "  $URL"
curl -fL --progress-bar -o "$TMP/libusb.tar.bz2" "$URL"
tar -xjf "$TMP/libusb.tar.bz2" -C "$TMP"
SRC="$TMP/libusb-${VERSION}"

mkdir -p Vendor
for ARCH in arm64 x86_64; do
  echo "Building libusb for $ARCH..."
  BUILD="$TMP/build-$ARCH"
  mkdir -p "$BUILD"
  ( cd "$BUILD" && "$SRC/configure" --quiet --disable-shared --enable-static --disable-udev ac_cv_func_pipe2=no \
      --host="$([ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64)-apple-darwin" \
      CC="clang -arch $ARCH -mmacosx-version-min=14.0" >/dev/null && make -j4 >/dev/null )
  clang -arch "$ARCH" -mmacosx-version-min=14.0 -O2 -Wall \
    -I "$SRC/libusb" "$ROOT/Helper/blippy-mtp.c" "$BUILD/libusb/.libs/libusb-1.0.a" \
    -framework IOKit -framework CoreFoundation -framework Security \
    -o "$TMP/blippy-mtp-$ARCH"
done

lipo -create "$TMP/blippy-mtp-arm64" "$TMP/blippy-mtp-x86_64" -output Vendor/blippy-mtp
cp "$SRC/COPYING" Vendor/libusb-COPYING.txt
chmod +x Vendor/blippy-mtp
cp "$SRC/COPYING" LICENSES/libusb-LGPL-2.1.txt
echo "Built: $(lipo -archs Vendor/blippy-mtp)  ->  Vendor/blippy-mtp"
