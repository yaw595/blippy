#!/bin/bash
# For forks: replaces the current maintainer's identity (GitHub name, support link, bundle ID) with yours.
#
#   scripts/set-identity.sh --github YOUR_USERNAME [--coffee https://example.com/support] [--bundle-id com.example.Blippy]
#
# Run it once, before your first release build. It edits Blippy/AppInfo.swift, the Xcode project, the
# README/docs and the GitHub templates. Review the result with `git diff`.
set -euo pipefail
cd "$(dirname "$0")/.."

GITHUB=""; COFFEE=""; BUNDLE_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --github) GITHUB="$2"; shift 2 ;;
    --coffee) COFFEE="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
[ -n "$GITHUB" ] || { echo "Usage: $0 --github USERNAME [--coffee URL] [--bundle-id ID]"; exit 1; }
LOWER="$(echo "$GITHUB" | tr '[:upper:]' '[:lower:]')"
[ -n "$BUNDLE_ID" ] || BUNDLE_ID="io.github.$LOWER.Blippy"

# What the project says right now
OLD_OWNER="$(sed -n 's/.*static let githubOwner = "\(.*\)".*/\1/p' Blippy/AppInfo.swift)"
OLD_COFFEE="$(sed -n 's/.*static let coffeeLink = "\(.*\)".*/\1/p' Blippy/AppInfo.swift)"
OLD_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \(.*\);/\1/p' Blippy.xcodeproj/project.pbxproj | grep -v ShareExtension | head -1)"
esc() { printf '%s' "$1" | sed 's/[][\.*^$/|&]/\\&/g'; }

# Swift constants
sed -i '' "s|static let githubOwner = \".*\"|static let githubOwner = \"$GITHUB\"|" Blippy/AppInfo.swift
if [ -n "$COFFEE" ]; then
  sed -i '' "s|static let coffeeLink = \".*\"|static let coffeeLink = \"$COFFEE\"|" Blippy/AppInfo.swift
fi

# Docs and GitHub files
FILES=$(grep -rlF "$OLD_OWNER" README.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md docs .github 2>/dev/null || true)
for f in $FILES; do
  sed -i '' "s|$(esc "$OLD_OWNER")|$GITHUB|g" "$f"
done
if [ -n "$COFFEE" ] && [ -n "$OLD_COFFEE" ]; then
  for f in $(grep -rlF "$OLD_COFFEE" README.md .github docs 2>/dev/null || true); do
    sed -i '' "s|$(esc "$OLD_COFFEE")|$COFFEE|g" "$f"
  done
fi

# Bundle identifiers (the app, and the Share extension inside it)
sed -i '' "s|$(esc "$OLD_ID")|$BUNDLE_ID|g" Blippy.xcodeproj/project.pbxproj
sed -i '' "s|$(esc "$OLD_ID")\.queue|$BUNDLE_ID.queue|" NearbyShare/NearbyConnection.swift 2>/dev/null || true

echo "GitHub:     $OLD_OWNER -> $GITHUB"
echo "Bundle ID:  $OLD_ID -> $BUNDLE_ID (Share extension: $BUNDLE_ID.ShareExtension)"
echo "Support:    ${COFFEE:-unchanged}"
echo "Done. Review with: git diff"
