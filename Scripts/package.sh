#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/LingoLive.app"
[[ -x "$app/Contents/MacOS/LingoLive" ]] || Scripts/build.sh
codesign --verify --deep --strict "$app"
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
minimum="$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/lingolive-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
folder="$stage/LingoLive"
mkdir -p "$folder"
ditto "$app" "$folder/LingoLive.app"
cp Scripts/install.sh "$folder/install.sh"
cp README.md "$folder/README.md"
cat > "$folder/安装语流.command" <<'COMMAND'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./install.sh "$PWD/LingoLive.app"
COMMAND
chmod +x "$folder/安装语流.command"
zip="$PWD/build/LingoLive-$version-$(uname -m)-macOS$minimum.zip"
ditto -c -k --sequesterRsrc --keepParent "$folder" "$zip"
echo "$zip"
