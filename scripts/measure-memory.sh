#!/usr/bin/env bash
# Measures Kitbag's idle memory footprint with all tools enabled vs all disabled.
# Usage: ./scripts/measure-memory.sh [path/to/Kitbag.app]   (run scripts/build.sh first)
# Note: it writes the tool toggles in Kitbag's preferences and quits any running Kitbag.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Kitbag.app}"
ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
# The app is sandboxed, so its preferences live in its container, not ~/Library/Preferences.
PREFS="$HOME/Library/Containers/$ID/Data/Library/Preferences/$ID"
TOOLS=(fileshelf systemmonitor speedtest devtools blip audio)  # keep in sync with App/Sources/AllTools.swift
pkill -x Kitbag 2>/dev/null || true; sleep 1
# Launch once so the sandbox container exists.
"$APP/Contents/MacOS/Kitbag" >/dev/null 2>&1 & first=$!; sleep 3; kill $first; wait $first 2>/dev/null || true

measure() { # $1 = true|false
  for t in "${TOOLS[@]}"; do defaults write "$PREFS" "kitbag.enabled.$t" -bool "$1"; done
  "$APP/Contents/MacOS/Kitbag" >/dev/null 2>&1 &
  local pid=$!
  sleep 5
  echo "--- tools enabled=$1 (pid $pid)"
  footprint -p "$pid" 2>/dev/null | grep -E "Footprint|phys_footprint" | head -3
  ps -o rss= -p "$pid" | awk '{printf "RSS: %.1f MB\n", $1/1024}'
  kill "$pid"; wait "$pid" 2>/dev/null || true
}
measure false
measure true
