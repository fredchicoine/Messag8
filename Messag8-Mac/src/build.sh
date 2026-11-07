#!/bin/bash
# Construit Messag8.app à partir de main.swift
set -e
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Les outils de développement Apple ne sont pas installés."
  echo "Lancez :  xcode-select --install   puis relancez ce script."
  exit 1
fi

APP="../Messag8.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp logo.png "$APP/Contents/Resources/logo.png"

# Icône de l'application (à partir de icon.png 1024x1024)
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || echo "(icône non générée)"

echo "Compilation en cours (1 à 2 minutes)..."
if swiftc -O -swift-version 5 -target arm64-apple-macos11.0 -o "$TMP/arm64" main.swift \
   && swiftc -O -swift-version 5 -target x86_64-apple-macos11.0 -o "$TMP/x86_64" main.swift; then
  lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$APP/Contents/MacOS/Messag8"
else
  echo "Compilation universelle impossible, compilation pour ce Mac seulement..."
  swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/Messag8" main.swift
fi
rm -rf "$TMP"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
xattr -cr "$APP" 2>/dev/null || true
touch "$APP"

echo ""
echo "Terminé :  $(cd .. && pwd)/Messag8.app"
open -R "$APP" 2>/dev/null || true
