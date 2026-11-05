#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
RIME_PREFIX="$(brew --prefix librime)"
OPENCC_PREFIX="$(brew --prefix opencc)"
ARCH="$(uname -m)"
MIN_MACOS=26.4
# Keep the internal bundle path stable across the YuliuType branding update.
APP="$ROOT/build/LingoLive.app"
SETUP="$APP/Contents/Resources/LingoLive Setup.app"
RIME_DATA="$APP/Contents/Resources/Rime"
NOTICES="$APP/Contents/Resources/Notices"
SIGN_ID="${CODESIGN_IDENTITY:--}"
LUNA_REV=56b934b099dfbeab842320f13aa8b461a6ab3e42
LUNA_SHA=876c7ba559794f476abf7195a255aea29000cee281e6f5ec664928dce018bd90

[[ -f "$RIME_PREFIX/include/rime_api.h" ]] || { echo '请先运行 brew install librime'; exit 1; }
mkdir -p .cache build
fetch_data() {
    local project="$1" revision="$2" digest="$3" archive=".cache/$1.tar.gz"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 --connect-timeout 15 --max-time 90 \
            "https://codeload.github.com/rime/rime-$project/tar.gz/$revision" -o "$archive.tmp"
        mv "$archive.tmp" "$archive"
    fi
    printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
    tar -xf "$archive" -C .cache
}
ESSAY_REV=054920de4f54c9e5994276a96a4fc2a35cb51aa3
fetch_data luna-pinyin "$LUNA_REV" "$LUNA_SHA"
fetch_data essay "$ESSAY_REV" 3339b40aae91b0216d393aeccc6a8f7daad56a1f3a5e1ffcf464c80690d1b6ce
LUNA="$ROOT/.cache/rime-luna-pinyin-$LUNA_REV"
ESSAY="$ROOT/.cache/rime-essay-$ESSAY_REV"

rm -rf "$APP"
mkdir -p "$APP/Contents/"{MacOS,Frameworks} "$RIME_DATA" "$NOTICES" "$SETUP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/Setup-Info.plist "$SETUP/Contents/Info.plist"
xcrun swift Scripts/draw-icon.swift "$APP/Contents/Resources/InputIcon.tiff"
cp Resources/*.yaml "$RIME_DATA/"
cp "$LUNA/LICENSE" "$NOTICES/luna-pinyin-LICENSE"
cp "$LUNA/AUTHORS" "$NOTICES/luna-pinyin-AUTHORS"
cp "$LUNA/luna_pinyin.dict.yaml" "$LUNA/pinyin.yaml" "$ESSAY/essay.txt" "$RIME_DATA/"
cp "$ESSAY/LICENSE" "$NOTICES/essay-LICENSE"
cp "$ESSAY/AUTHORS" "$NOTICES/essay-AUTHORS"
mkdir -p "$RIME_DATA/opencc"
cp "$OPENCC_PREFIX/share/opencc/"{t2s.json,CJK_Compatibility_Ideographs.ocd2,TSPhrases.ocd2,TSCharactersExt.ocd2,TSCharacters.ocd2} "$RIME_DATA/opencc/"
plutil -lint "$APP/Contents/Info.plist" "$SETUP/Contents/Info.plist"

xcrun clang -O2 -arch "$ARCH" -mmacosx-version-min="$MIN_MACOS" -I "$RIME_PREFIX/include" \
    -c Sources/RimeBridge/bridge.c -o build/RimeBridge.o
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macosx$MIN_MACOS" -I Sources/RimeBridge \
    -L "$RIME_PREFIX/lib" -lrime -Xlinker -headerpad_max_install_names \
    Sources/{main,Controller,Palette,Rime,Translator}.swift build/RimeBridge.o -o "$APP/Contents/MacOS/LingoLive"
xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macosx$MIN_MACOS" -parse-as-library \
    Sources/{Setup,Translator}.swift -o "$SETUP/Contents/MacOS/LingoLiveSetup"
REQUIRED_MACOS="$(python3 Scripts/bundle-libs.py "$APP/Contents/MacOS/LingoLive" "$APP/Contents/Frameworks" "$NOTICES" "$(brew --prefix)" "$MIN_MACOS")"
plutil -replace LSMinimumSystemVersion -string "$REQUIRED_MACOS" "$APP/Contents/Info.plist"
echo "此构建需要 macOS $REQUIRED_MACOS 或更新版本。"

SIGN_FLAGS=(--timestamp=none)
if [[ "$SIGN_ID" != "-" ]]; then SIGN_FLAGS=(--options runtime --timestamp); fi
for library in "$APP/Contents/Frameworks/"*.dylib; do
    codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" "$library"
done
codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" "$SETUP"
codesign --force --sign "$SIGN_ID" "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
