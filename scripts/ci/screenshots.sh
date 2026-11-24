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
xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -sampleData
sleep 20

shot() {
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1
  echo "captured $1"
}

# Tabs: open directly. Sheets: return Home first so one sheet fully closes before the next opens.
tab() { xcrun simctl openurl "$UDID" "secondbrain://$1"; sleep "${2:-6}"; }
sheet() {
  xcrun simctl openurl "$UDID" "secondbrain://home"; sleep 3
  xcrun simctl openurl "$UDID" "secondbrain://$1"; sleep "${2:-7}"
}

shot 01-home
sheet "capture?text=Have%20Stock%202%20work%20the%20remix%20by%20end%20of%20shift" 8; shot 02-capture-hand-off
sheet "capture?text=Pre-use%20inspection%20on%20the%20walkie%20stacker%20before%20Black%20Friday" 8; shot 03-capture-safety
tab matrix; shot 04-matrix
tab tasks; shot 05-tasks
tab associates; shot 06-team
tab notes; shot 07-notes
sheet season; shot 08-season-planner
sheet terms; shot 09-store-terms
sheet "terms?q=FTPR"; shot 10-store-terms-search
sheet shift 8; shot 11-end-my-shift
sheet planner 8; shot 12-planner
sheet review 8; shot 13-weekly-review
sheet settings; shot 14-settings
tab home 3

ls -la "$OUT"
