#!/bin/bash
# Builds build/Sweep.app from the Swift package.
#   VERSION=1.2.0  stamp this version into the bundle (default: the one in Info.plist)
#   UNIVERSAL=1    build for both Apple silicon and Intel
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Sweep.app"
ICON="Resources/AppIcon.icns"

BUILD=(swift build -c release)
if [ "${UNIVERSAL:-0}" = 1 ]; then
    BUILD+=(--arch arm64 --arch x86_64)
fi
"${BUILD[@]}"
BINARY="$("${BUILD[@]}" --show-bin-path)/Sweep"

if [ ! -f "$ICON" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    swift Scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    done
    for size in 16 128 256; do
        sips -z $((size * 2)) $((size * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
    sips -z 64 64 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$ICON"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Sweep"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
        -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Creata $APP"
