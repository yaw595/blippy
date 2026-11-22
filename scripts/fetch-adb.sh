#!/bin/bash
# Downloads Google's official Android SDK Platform-Tools for macOS and copies `adb`
# (and its NOTICE file) into Vendor/. Blippy bundles adb for cable transfers.
# Usage: scripts/fetch-adb.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -x Vendor/adb ] && [ "${1:-}" != "--force" ]; then
  echo "Vendor/adb already exists ($(Vendor/adb version | head -1)). Use --force to replace it."
  exit 0
fi

URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Android SDK Platform-Tools from Google:"
echo "  $URL"
curl -fL --progress-bar -o "$TMP/platform-tools.zip" "$URL"
unzip -q "$TMP/platform-tools.zip" -d "$TMP"

mkdir -p Vendor
cp "$TMP/platform-tools/adb" Vendor/adb
cp "$TMP/platform-tools/NOTICE.txt" Vendor/adb-NOTICE.txt
xattr -cr Vendor/adb 2>/dev/null || true
chmod +x Vendor/adb
echo "Installed: $(Vendor/adb version | head -1)"
