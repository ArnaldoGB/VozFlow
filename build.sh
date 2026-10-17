#!/bin/bash
# Builds VozFlow.app (universal: Apple Silicon + Intel) next to this project folder.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="VozFlow"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
OUT="../$APP_NAME.app"

# Command Line Tools can ship a default SDK newer than the compiler; prefer the macOS 26 SDK when present.
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/obj"

echo "→ Compilando (arm64)…"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o "$BUILD/obj/$APP_NAME-arm64"
echo "→ Compilando (x86_64)…"
swiftc -O -swift-version 5 -target x86_64-apple-macos14.0 Sources/*.swift -o "$BUILD/obj/$APP_NAME-x86_64"
lipo -create "$BUILD/obj/$APP_NAME-arm64" "$BUILD/obj/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"

echo "→ Gerando ícone…"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
swift Tools/make_icon.swift "$BUILD/icon_1024.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp Info.plist "$APP/Contents/Info.plist"

SIGN_KC="$HOME/Library/Keychains/vozflow-signing.keychain-db"
SIGN_ID="VozFlow Local Signing"
if [ -f "$SIGN_KC" ]; then
    echo "→ Assinando ($SIGN_ID)…"
    security unlock-keychain -p "vozflow-local" "$SIGN_KC"
    codesign --force --sign "$SIGN_ID" "$APP"
else
    echo "→ Assinando (ad-hoc — rode Tools/setup_signing.sh para manter as permissões entre builds)…"
    codesign --force --sign - "$APP"
fi

rm -rf "$OUT"
ditto "$APP" "$OUT"
# Keep a single copy of the app so Spotlight and the privacy lists don't show a duplicate.
rm -rf "$BUILD"
echo "✓ Pronto: $(cd .. && pwd)/$APP_NAME.app"
