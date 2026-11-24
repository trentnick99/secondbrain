#!/bin/bash
# Installs the simulator build, loads the fictional sample data and captures each main screen.
# Usage: scripts/ci/screenshots.sh <simulator-udid> <path/to/SecondBrain.app> <output-dir>
set -euo pipefail

UDID="$1"
APP="$2"
OUT="$3"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -sampleData >/dev/null
sleep 20

shot() {
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1
  echo "captured $1"
}

# Each screen is a fresh launch straight onto that screen (test mode only), because opening
# links from outside the app makes iOS ask "Open in Second Brain?" and blocks the screen.
screen() {
  local name="$1" link="$2" wait="${3:-9}"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -sampleData -openURL "secondbrain://$link" >/dev/null
  sleep "$wait"
  shot "$name"
}

shot 01-home
screen 02-capture-hand-off "capture?text=Have%20Stock%202%20work%20the%20remix%20by%20end%20of%20shift" 11
screen 03-capture-safety "capture?text=Pre-use%20inspection%20on%20the%20walkie%20stacker%20before%20Black%20Friday" 11
screen 04-matrix matrix
screen 05-tasks tasks
screen 06-team associates
screen 07-notes notes
screen 08-season-planner season
screen 09-store-terms terms
screen 10-store-terms-search "terms?q=FTPR"
screen 11-end-my-shift shift 10
screen 12-planner planner 10
screen 13-weekly-review review 10
screen 14-settings settings

ls -la "$OUT"
