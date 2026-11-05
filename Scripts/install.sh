#!/bin/bash
set -euo pipefail
DEFAULT_APP="$(cd "$(dirname "$0")/.." && pwd)/build/LingoLive.app"
SOURCE="${1:-$DEFAULT_APP}"
DEST="$HOME/Library/Input Methods/LingoLive.app"
SYSTEM_APP="/Library/Input Methods/LingoLive.app"
if [[ -e "$SYSTEM_APP" ]]; then
    echo "已存在系统版语流。请用系统安装包更新，避免同时安装两个副本。"
    exit 1
fi
[[ "$SOURCE" != "$DEST" ]] || { echo "语流已在安装位置。"; exit 0; }
[[ -x "$SOURCE/Contents/MacOS/LingoLive" ]] || { echo "找不到 $SOURCE"; exit 1; }
codesign --verify --deep --strict "$SOURCE"
mkdir -p "$(dirname "$DEST")"
if [[ -e "$DEST" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")"
    [[ "$existing_id" == com.lingolive.inputmethod.Mac ]] || { echo "目标位置已有其他应用：$DEST"; exit 1; }
    pkill -f "^$DEST/Contents/MacOS/LingoLive($| )" || true
    backup="$(mktemp -d "${TMPDIR:-/tmp}/lingolive.XXXXXX")"
    mv "$DEST" "$backup/LingoLive.app"
fi
if ! ditto "$SOURCE" "$DEST"; then
    [[ -z "${backup:-}" ]] || mv "$backup/LingoLive.app" "$DEST"
    exit 1
fi
"$DEST/Contents/MacOS/LingoLive" --prepare-rime
"$DEST/Contents/MacOS/LingoLive" --register || {
    status=$?
    [[ "$status" == 2 ]] || exit "$status"
}
if [[ "${LINGOLIVE_NO_SETUP:-}" != 1 ]]; then
    open "$DEST/Contents/Resources/LingoLive Setup.app"
fi
echo '添加后，在 macOS 输入法菜单选择「语流」。如果列表没有更新，请重新打开系统设置；仍无结果时注销再登录。'
