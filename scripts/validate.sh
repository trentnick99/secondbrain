#!/usr/bin/env bash
# Runs every check that doesn't need the iOS SDK. Works on macOS or Linux with a Swift toolchain.
#   ./scripts/validate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶ Engine tests (SecondBrainCore)"
(cd Packages/SecondBrainCore && swift test 2>&1 | grep -E "Executed|error|failed" | tail -3)

echo "▶ Swift syntax check (app, shared, widgets, tests)"
count=0
while IFS= read -r f; do
  swiftc -parse "$f" >/dev/null
  count=$((count + 1))
done < <(find App Shared Widgets Watch Tests -name '*.swift' | sort)
echo "  $count files parsed"

echo "▶ Project structure"
python3 scripts/validate_project.py | tail -1

if command -v xcodebuild >/dev/null 2>&1; then
  echo "▶ Xcode build (simulator)"
  xcodebuild -project SecondBrain.xcodeproj -scheme SecondBrain \
    -destination 'generic/platform=iOS Simulator' -quiet build
fi
echo "✔ Done"
