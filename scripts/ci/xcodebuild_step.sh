#!/usr/bin/env bash
# Runs an xcodebuild command, keeps the full log, and on failure prints a clean list of compiler
# errors to the job log and the run summary (so they're easy to read from a phone).
#   scripts/ci/xcodebuild_step.sh <log-name> xcodebuild <args...>
set -uo pipefail
name="$1"; shift
mkdir -p build/logs
log="build/logs/${name}.log"

# The result bundle, if the command writes one: failure messages from parallel test runs only live there.
bundle=""; prev=""
for arg in "$@"; do [ "$prev" = "-resultBundlePath" ] && bundle="$arg"; prev="$arg"; done

# Keep the full log in a file, and stream test progress and errors live to the job log.
run() {
  "$@" 2>&1 | tee "$log" | grep --line-buffered -E "Test Case .*(passed|failed)|error:|\*\* .* \*\*|Testing started|Test Suite .* (passed|failed)|SCHEMA_HASH"
  status=${PIPESTATUS[0]}
}
run "$@"

# A cloud simulator sometimes never finishes starting accessibility, so no UI test runs at all.
# That's the machine, not the app: restart the simulators once and try again.
if [ $status -ne 0 ] && grep -q "failed to initialize for UI testing" "$log"; then
  echo "::warning::The simulator didn't start UI testing; restarting it and trying once more."
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  sleep 10
  [ -n "$bundle" ] && rm -rf "$bundle"
  run "$@"
fi

grep -E "^\*\* .* (SUCCEEDED|FAILED) \*\*" "$log" | tail -2 || true
if [ $status -ne 0 ]; then
  if [ -n "$bundle" ] && [ -d "$bundle" ]; then
    echo "::group::Test failures from ${name}"
    xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for f in data.get("testFailures", []):
    print("TEST FAILURE:", f.get("testIdentifierString") or f.get("testName"), "-", f.get("failureText"))
' | tee -a "$log" || true
    echo "::endgroup::"
  fi
  errors=$(grep -E "(error:|Error:|Testing failed|failed \(|XCTAssert)" "$log" | grep -v "^note:" | sort -u | head -150)
  echo "::group::Errors from ${name}"
  if [ -n "$errors" ]; then echo "$errors"; else tail -80 "$log"; fi
  echo "::endgroup::"
  {
    echo "### ❌ ${name} failed"
    echo '```'
    if [ -n "$errors" ]; then echo "$errors" | head -60; else tail -40 "$log"; fi
    echo '```'
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  # Annotate files so errors show inline in the GitHub UI.
  echo "$errors" | grep -E "^/.+\.swift:[0-9]+:[0-9]+: error:" | head -30 | while IFS= read -r line; do
    file=$(echo "$line" | cut -d: -f1 | sed "s|^${GITHUB_WORKSPACE:-$PWD}/||")
    ln=$(echo "$line" | cut -d: -f2)
    msg=$(echo "$line" | cut -d: -f5-)
    echo "::error file=${file},line=${ln}::${msg}"
  done
  exit $status
fi
echo "### ✅ ${name} succeeded" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
