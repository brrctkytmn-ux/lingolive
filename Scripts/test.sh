#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/LingoLive.app"
[[ -x "$app/Contents/MacOS/LingoLive" ]] || Scripts/build.sh
state="$(mktemp -d "${TMPDIR:-/tmp}/lingolive-test.XXXXXX")"
trap 'rm -rf "$state"' EXIT
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/LingoLive" --probe-rime "$state/rime"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx26.4" -parse-as-library \
    Sources/Translator.swift Tests/TranslationBenchmark.swift -o "$state/benchmark"
"$state/benchmark"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx26.4" -parse-as-library -I Sources/RimeBridge \
    "$app/Contents/Frameworks/librime.1.dylib" -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    Sources/{Controller,Palette,Rime,Translator}.swift Tests/CompositionSmoke.swift build/RimeBridge.o -o "$state/composition"
"$state/composition" "$app/Contents/Resources/Rime" "$state/composition-rime"
