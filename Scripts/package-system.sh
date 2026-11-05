#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/LingoLive.app"
[[ -x "$app/Contents/MacOS/LingoLive" ]] || Scripts/build.sh
/usr/bin/codesign --verify --deep --strict "$app"
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
minimum="$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/lingolive-system.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/payload"
/usr/bin/ditto --norsrc --noextattr "$app" "$stage/payload/LingoLive.app"
/usr/bin/codesign --verify --deep --strict "$stage/payload/LingoLive.app"
/usr/bin/pkgbuild --analyze --root "$stage/payload" "$stage/components.plist"
# Neither the input method nor the embedded settings app may be relocated
# to an older per-user path by Installer.
index=0
while plutil -extract "$index.BundleIsRelocatable" raw "$stage/components.plist" >/dev/null 2>&1; do
    plutil -replace "$index.BundleIsRelocatable" -bool NO "$stage/components.plist"
    index=$((index + 1))
done
[[ "$index" -gt 0 ]]
output="$PWD/build/LingoLive-$version-$(uname -m)-macOS$minimum-System.pkg"
/usr/bin/pkgbuild --root "$stage/payload" --component-plist "$stage/components.plist" \
    --identifier com.lingolive.installer.system --version "$version" --install-location "/Library/Input Methods" \
    --scripts Scripts/system-package "$output"
echo "$output"
