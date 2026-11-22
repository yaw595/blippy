#!/bin/bash
# Fills in your project identity in one go: GitHub username, Buy Me a Coffee link and the bundle ID.
#
#   scripts/set-identity.sh --github YOUR_USERNAME [--coffee https://buymeacoffee.com/you] [--bundle-id com.example.Blippy]
#
# Run it once, before your first release build. It edits AppInfo.swift, the Xcode project,
# the README/docs and the GitHub templates. Review the result with `git diff`.
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

# Swift constants
sed -i '' "s|static let githubOwner = \"YOUR-GITHUB-USERNAME\"|static let githubOwner = \"$GITHUB\"|" NearDrop/AppInfo.swift
if [ -n "$COFFEE" ]; then
  sed -i '' "s|static let coffeeLink = \"\"|static let coffeeLink = \"$COFFEE\"|" NearDrop/AppInfo.swift
fi

# Docs and GitHub files
FILES=$(grep -rlE "YOUR-GITHUB-USERNAME|YOUR-COFFEE-NAME|buymeacoffee.com/YOUR" README.md CONTRIBUTING.md CODE_OF_CONDUCT.md docs .github 2>/dev/null || true)
for f in $FILES; do
  sed -i '' "s|YOUR-GITHUB-USERNAME|$GITHUB|g" "$f"
  if [ -n "$COFFEE" ]; then
    NAME="${COFFEE##*/}"
    sed -i '' -e "s|https://buymeacoffee.com/YOUR-COFFEE-NAME|$COFFEE|g" -e "s|YOUR-COFFEE-NAME|$NAME|g" "$f"
  fi
done

# Bundle identifiers (the app, and the Share extension inside it)
sed -i '' "s|me\\.grishka\\.NearDrop|$BUNDLE_ID|g" NearDrop.xcodeproj/project.pbxproj

echo "GitHub:     $GITHUB"
echo "Bundle ID:  $BUNDLE_ID (Share extension: $BUNDLE_ID.ShareExtension)"
echo "Coffee:     ${COFFEE:-not set (the support section stays hidden)}"
echo "Done. Review with: git diff"
