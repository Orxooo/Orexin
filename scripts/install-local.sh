#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
SOURCE_APP="${1:?Usage: install-local.sh /absolute/path/Orexin.app}"
TARGET_APP=/Applications/Orexin.app
BACKUP_DIR="${OREXIN_BACKUP_DIR:-$HOME/Library/Logs/Orexin/LocalUpdates/$(date +%Y%m%d-%H%M%S)}"
codesign --verify --strict "$SOURCE_APP"
if [[ "$SOURCE_APP" == "$TARGET_APP" ]]; then
  print -u2 'Source must differ from installed app'; exit 1
fi
if [[ -d "$TARGET_APP" ]]; then
  autoload -Uz is-at-least
  INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET_APP/Contents/Info.plist")
  INSTALLED_HANDOFF=$(/usr/libexec/PlistBuddy -c 'Print :OrexinHelperHandoffSupported' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$INSTALLED_HANDOFF" != true ]] && ! is-at-least 1.1.2 "$INSTALLED_VERSION"; then
    print -u2 'The installed version predates helper handoff. Use a supervised migration for this first update.'
    exit 1
  fi
  "$TARGET_APP/Contents/Helpers/orexin" service-start >/dev/null
  # This command refuses replacement while work or commands remain active.
  "$TARGET_APP/Contents/MacOS/Orexin" --prepare-helper-update
  "$TARGET_APP/Contents/Helpers/orexin" service-stop >/dev/null
  /usr/bin/pkill -x Orexin || true
  mkdir -p "$BACKUP_DIR"
  mv "$TARGET_APP" "$BACKUP_DIR/Orexin.app"
fi
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/usr/bin/open "$TARGET_APP"
