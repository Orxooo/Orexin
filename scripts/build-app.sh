#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Orxooo
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="${OREXIN_BUILD_DIR:-/tmp/orexin-build}"
CORE_BUILD_DIR="${OREXIN_CORE_BUILD_DIR:-${BUILD_DIR}-core}"
OUTPUT_DIR="${OREXIN_OUTPUT_DIR:-/tmp/orexin-dist}"
BUILD_CHANNEL="${OREXIN_BUILD_CHANNEL:-dev}"
case "$BUILD_CHANNEL" in
  dev|stable) ;;
  *) print -u2 'OREXIN_BUILD_CHANNEL must be dev or stable'; exit 1 ;;
esac
cd "$PROJECT_DIR"
swift build -c release --arch arm64 --scratch-path "$BUILD_DIR"
APP="$OUTPUT_DIR/Orexin.app"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BUILD_DIR/release/orexin" "$APP/Contents/Helpers/orexin"
cp "$BUILD_DIR/release/WakeMac" "$APP/Contents/MacOS/Orexin"
cp "$BUILD_DIR/release/WakeMacPowerHelper" "$APP/Contents/MacOS/OrexinPowerHelper"
cp "$PROJECT_DIR/Resources/com.orxooo.Orexin.PowerHelper.plist" "$APP/Contents/Library/LaunchDaemons/"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${OREXIN_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${OREXIN_VERSION#v}" "$APP/Contents/Info.plist"
fi
if [[ "$BUILD_CHANNEL" == dev ]]; then
  /usr/libexec/PlistBuddy -c 'Set :OrexinReleaseChannel Dev' "$APP/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :OrexinReleaseChannel string Dev' "$APP/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c 'Delete :OrexinReleaseChannel' "$APP/Contents/Info.plist" 2>/dev/null || true
fi
mkdir -p "$CORE_BUILD_DIR"
CORE_INFO="$CORE_BUILD_DIR/OrexinCore-Info.plist"
cp "$APP/Contents/Info.plist" "$CORE_INFO"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable OrexinCore' "$CORE_INFO"
/usr/libexec/PlistBuddy -c 'Delete :LSUIElement' "$CORE_INFO"
/usr/libexec/PlistBuddy -c 'Add :LSBackgroundOnly bool true' "$CORE_INFO"
swift build -c release --arch arm64 --scratch-path "$CORE_BUILD_DIR" --product WakeMac \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$CORE_INFO"
cp "$CORE_BUILD_DIR/release/WakeMac" "$APP/Contents/Helpers/OrexinCore"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/Orexin.sdef" "$APP/Contents/Resources/Orexin.sdef"
mkdir -p "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/Licenses"
rsync -a --delete "$PROJECT_DIR/Assets/Fonts/" "$APP/Contents/Resources/Fonts/"
rsync -a --delete "$PROJECT_DIR/Assets/Licenses/" "$APP/Contents/Resources/Licenses/"
cp "$PROJECT_DIR/LICENSE" "$APP/Contents/Resources/Licenses/Orexin-GPL-3.0.txt"
cp "$PROJECT_DIR/NOTICE" "$APP/Contents/Resources/Licenses/Orexin-NOTICE.txt"
for localization in "$PROJECT_DIR"/Resources/Localization/*.lproj; do
  [[ -d "$localization" ]] || continue
  cp -R "$localization" "$APP/Contents/Resources/"
done
cp "$PROJECT_DIR/Assets/PowerTerminal.png" "$APP/Contents/Resources/PowerTerminal.png"
cp "$PROJECT_DIR/Assets/OrbitalMoon.png" "$APP/Contents/Resources/OrbitalMoon.png"
cp "$PROJECT_DIR/Assets/OrbitalCore.png" "$APP/Contents/Resources/OrbitalCore.png"
cp "$PROJECT_DIR/Assets/OrbitalZima.png" "$APP/Contents/Resources/OrbitalZima.png"
cp "$PROJECT_DIR/Assets/Orbital2049.png" "$APP/Contents/Resources/Orbital2049.png"
mkdir -p "$APP/Contents/Resources/BladeRunner2049"
rsync -a --delete "$PROJECT_DIR/Assets/BladeRunner2049/" "$APP/Contents/Resources/BladeRunner2049/"
mkdir -p "$APP/Contents/Resources/ZimaBlue"
rsync -a --delete "$PROJECT_DIR/Assets/ZimaBlue/" "$APP/Contents/Resources/ZimaBlue/"
mkdir -p "$APP/Contents/Resources/Tron"
rsync -a --delete "$PROJECT_DIR/Assets/Tron/" "$APP/Contents/Resources/Tron/"
mkdir -p "$APP/Contents/Resources/Sounds"
rsync -a --delete --delete-excluded --include='*-click.wav' --exclude='*' "$PROJECT_DIR/Assets/Sounds/" "$APP/Contents/Resources/Sounds/"
codesign --force --options runtime --sign "${OREXIN_SIGN_IDENTITY:--}" "$APP/Contents/Helpers/orexin"
codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/Orexin.entitlements" \
  --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" \
  --sign "${OREXIN_SIGN_IDENTITY:--}" "$APP/Contents/Helpers/OrexinCore"
cp "$APP/Contents/Helpers/orexin" "$OUTPUT_DIR/orexin"
codesign --force --options runtime --sign "${OREXIN_SIGN_IDENTITY:--}" --identifier com.orxooo.Orexin.PowerHelper "$APP/Contents/MacOS/OrexinPowerHelper"
codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/Orexin.entitlements" --sign "${OREXIN_SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
