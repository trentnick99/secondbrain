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
# Skip the keyboard's first-run "slide to type" tip so it doesn't cover the screen.
for domain in com.apple.Preferences com.apple.keyboard.preferences; do
  xcrun simctl spawn "$UDID" defaults write "$domain" DidShowContinuousPathIntroduction -bool true || true
  xcrun simctl spawn "$UDID" defaults write "$domain" DidShowGestureKeyboardIntroduction -bool true || true
done
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -sampleData -sampleSchedule -sampleRole >/dev/null
sleep 20

shot() {
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1
  echo "captured $1"
}

# Each screen is a fresh launch straight onto that screen (test mode only), because opening
# links from outside the app makes iOS ask "Open in Second Brain?" and blocks the screen.
screen() {
  local name="$1" link="$2" wait="${3:-14}"
  for attempt in 1 2 3 4; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    # shellcheck disable=SC2086
    xcrun simctl launch "$UDID" "$BUNDLE" -uiTesting -sampleData -sampleSchedule -sampleRole ${EXTRA_ARGS:-} -openURL "secondbrain://$link" >/dev/null
    sleep $((wait + attempt * 5))
    shot "$name"
    # Still launching, or still on Home? The slow simulator missed the screen — retry with more time.
    if ! python3 scripts/ci/screen_check.py "$OUT/01-home.png" "$OUT/$name.png"; then return; fi
    echo "  $name not ready yet (attempt $attempt)"
  done
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
IMPORT_TEXT="Subject%3A%20Market%20walk%20follow-up%0ATotal%20store%3A%0A-%20Clear%20all%20fire%20exits%20and%20keep%20Action%20Alley%20open%20for%20Black%20Friday%0AFood%0A-%20Fill%20the%20holes%20in%20dairy%20and%20frozen%20by%20Wednesday%0A-%20Rotate%20the%20bread%20aisle%20and%20pull%20out%20of%20date%20product%0AFresh%3A%0A-%20Wet%20wall%20needs%20culling%2C%20fix%20signage%20by%20tomorrow%0A%0APlease%20send%20me%20the%20pallet%20drop%20map%20by%20Friday."
screen 15-import-review "import?text=$IMPORT_TEXT" 12
screen 16-routines routines
screen 17-ask ask
screen 18-ask-answer "ask?q=Short%20staffed%20tonight%20and%20freight%20is%20behind%2C%20what%20first%3F" 8
screen 19-floor-walk walk
screen 20-import-scan-speak import
EXTRA_ARGS="-sampleWeather" screen 21-weather-alert home
screen 22-huddle huddle
screen 23-timeline timeline
screen 24-ask-freezer "ask?q=The%20frozen%20and%20dairy%20truck%20needs%20breaking%20down%20but%20the%20freezer%20door%20will%20not%20open%2C%20only%20manually" 8

ls -la "$OUT"
