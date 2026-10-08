#!/bin/bash
set -euo pipefail

mousepilot_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mousepilot_configuration="${1:-release}"
case "$mousepilot_configuration" in
  debug|release) ;;
  *) echo "Usage: scripts/build-app.sh [debug|release]" >&2; exit 2 ;;
esac

mousepilot_signing_identity="${MOUSEPILOT_SIGN_IDENTITY:-}"
if [ -z "$mousepilot_signing_identity" ]; then
  mousepilot_available_identities="$(security find-identity -v -p codesigning)"
  mousepilot_signing_identity="$(printf '%s\n' "$mousepilot_available_identities" | awk '/"Developer ID Application:/{print $2; exit}')"
  if [ -z "$mousepilot_signing_identity" ]; then
    mousepilot_signing_identity="$(printf '%s\n' "$mousepilot_available_identities" | awk '/"Apple Development:/{print $2; exit}')"
  fi
  if [ -z "$mousepilot_signing_identity" ]; then
    mousepilot_signing_identity="-"
    printf '%s\n' 'No signing certificate found: using ad hoc signing. After code changes, re-add MousePilot in macOS privacy settings.' >&2
  fi
fi

swift build --package-path "$mousepilot_root" --configuration "$mousepilot_configuration"
mousepilot_bin_dir="$(swift build --package-path "$mousepilot_root" --configuration "$mousepilot_configuration" --show-bin-path)"
mousepilot_app="$mousepilot_root/build/MousePilot-Gestures.app"
mkdir -p "$mousepilot_root/build"
mousepilot_staging="$(mktemp -d "${TMPDIR:-/tmp}/MousePilot-package.XXXXXX")"
trap 'rm -rf -- "$mousepilot_staging"' EXIT
mousepilot_new_app="$mousepilot_staging/MousePilot-Gestures.app"
mkdir -p "$mousepilot_new_app/Contents/MacOS" "$mousepilot_new_app/Contents/Resources"
cp "$mousepilot_bin_dir/MousePilot" "$mousepilot_new_app/Contents/MacOS/MousePilot"
cp "$mousepilot_root/Resources/Info.plist" "$mousepilot_new_app/Contents/Info.plist"
swift "$mousepilot_root/scripts/generate-icon.swift" "$mousepilot_staging/MousePilot.iconset"
iconutil -c icns "$mousepilot_staging/MousePilot.iconset" -o "$mousepilot_new_app/Contents/Resources/MousePilot.icns"
# Finder metadata can be inherited when files are copied from a managed folder.
xattr -cr "$mousepilot_new_app"
codesign --force --options runtime --sign "$mousepilot_signing_identity" --identifier dev.mousepilot.mac "$mousepilot_new_app"
codesign --verify --strict "$mousepilot_new_app"
# A zip preserves the verified bundle when the workspace is managed by a file
# provider that automatically attaches Finder metadata to application folders.
ditto -c -k --norsrc --noextattr --keepParent "$mousepilot_new_app" "$mousepilot_root/build/MousePilot-Gestures.zip"
# Replace a verified bundle without rewriting the executable of a running instance.
if [ -e "$mousepilot_app" ]; then
  mv "$mousepilot_app" "$mousepilot_staging/previous.app"
fi
if ! mv "$mousepilot_new_app" "$mousepilot_app"; then
  if [ -e "$mousepilot_staging/previous.app" ]; then
    mv "$mousepilot_staging/previous.app" "$mousepilot_app"
  fi
  exit 1
fi
xattr -cr "$mousepilot_app"
codesign --verify --strict "$mousepilot_app"
printf '\nBuilt: %s\n' "$mousepilot_app"
printf 'Archive: %s\n' "$mousepilot_root/build/MousePilot-Gestures.zip"
