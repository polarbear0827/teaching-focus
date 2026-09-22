#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${TEACHINGFOCUS_APP_PATH:-.build/artifacts/TeachingFocus.app}"
OUT="${TEACHINGFOCUS_PKG_PATH:-../TeachingFocus-v1.0.0-beta.5-arm64.pkg}"
STAGE=$(mktemp -d /tmp/teachingfocus-pkg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/root/Applications"
ditto --norsrc --noextattr "$APP" "$STAGE/root/Applications/TeachingFocus.app"
xattr -cr "$STAGE/root"
codesign --verify --deep --strict "$STAGE/root/Applications/TeachingFocus.app"
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$STAGE/components.plist"
pkgbuild --root "$STAGE/root" --component-plist "$STAGE/components.plist" --identifier tw.teachingfocus.mac.pkg --version 1.0.0.5 --install-location / --ownership recommended "$OUT"
pkgutil --payload-files "$OUT"
echo "Created unsigned PKG: $OUT"
