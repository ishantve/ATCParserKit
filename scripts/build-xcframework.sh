#!/usr/bin/env bash
#
# build-xcframework.sh
#
# Builds a STATIC ATCParserFFI.xcframework (iOS device + simulator) from the
# Swift package — the parser core plus the C ABI — and drops it into the Unity
# plugin folder. Static + C symbols is what Unity's [DllImport("__Internal")]
# expects (the plugin is statically linked into the app binary).
#
# Usage:  scripts/build-xcframework.sh
#
set -euo pipefail

SCHEME="ATCParserFFI"
LIB="libATCParserFFI.a"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
HEADERS="$BUILD/headers"
UNITY_IOS="$ROOT/platforms/unity/Runtime/Plugins/iOS"
OUT="$UNITY_IOS/ATCParserFFI.xcframework"

rm -rf "$BUILD" "$OUT"
mkdir -p "$HEADERS"
cp "$UNITY_IOS/atc_parser.h" "$HEADERS/"

build () {
  local destination="$1" sdk="$2"
  xcodebuild build \
    -scheme "$SCHEME" \
    -destination "$destination" \
    -sdk "$sdk" \
    -derivedDataPath "$DERIVED" \
    -configuration Release \
    MACH_O_TYPE=staticlib \
    SKIP_INSTALL=NO
}

echo "▸ Building static lib for iOS device…"
build "generic/platform=iOS"           "iphoneos"
echo "▸ Building static lib for iOS simulator…"
build "generic/platform=iOS Simulator" "iphonesimulator"

# SPM emits relocatable objects (ATCParserFFI.o + ATCParserKit.o) rather than a
# .a. Combine the FFI and its core dependency into one static archive per slice
# so the exported C symbols and everything they call are self-contained.
pack () {
  local products="$1" out="$2"
  libtool -static -o "$out" \
    "$products/ATCParserFFI.o" \
    "$products/ATCParserKit.o"
}

mkdir -p "$BUILD/ios" "$BUILD/sim"
pack "$DERIVED/Build/Products/Release-iphoneos"        "$BUILD/ios/$LIB"
pack "$DERIVED/Build/Products/Release-iphonesimulator" "$BUILD/sim/$LIB"

echo "▸ Creating xcframework…"
xcodebuild -create-xcframework \
  -library "$BUILD/ios/$LIB" -headers "$HEADERS" \
  -library "$BUILD/sim/$LIB" -headers "$HEADERS" \
  -output "$OUT"

echo "✅ Built $OUT"
echo "   Ready for the Unity package (Runtime/Plugins/iOS)."
