#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

stage="${1:-$PWD/.dist}"
configuration="${2:-release}"
mkdir -p "$stage"
stage="$(cd "$stage" && pwd)"
iconset="$stage/AppIcon.iconset"
bundle="$stage/NewsLingo.app"
mkdir -p "$iconset" "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
cp "$bin_dir/ReadProof" "$bundle/Contents/MacOS/ReadProof"
cp Distribution/Info.plist "$bundle/Contents/Info.plist"
ditto Distribution/AI-Skill "$bundle/Contents/Resources/AI-Skill"
cp Distribution/WordNet/WordNet.sqlite3 Distribution/WordNet/WordNet-LICENSE.txt "$bundle/Contents/Resources/"
if [[ ! -f "$stage/mark.png" || Scripts/draw-icon.swift -nt "$stage/mark.png" ]]; then
    swift Scripts/draw-icon.swift "$stage/mark.png"
fi
for dimension in 16 32 128 256 512; do
    sips -z "$dimension" "$dimension" "$stage/mark.png" --out "$iconset/icon_${dimension}x${dimension}.png" >/dev/null
    twice=$((dimension * 2))
    sips -z "$twice" "$twice" "$stage/mark.png" --out "$iconset/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - --identifier app.jugan.reader "$bundle"
codesign --verify --deep --strict "$bundle"
printf '%s\n' "$bundle"
