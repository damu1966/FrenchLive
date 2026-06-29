#!/bin/bash
set -e
BUNDLE=FrenchLive.app
swift build -c release 2>&1
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp .build/release/FrenchLive "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/"
codesign --sign - --entitlements Resources/FrenchLive.entitlements --deep "$BUNDLE"
echo "Built: $(pwd)/$BUNDLE"
