#!/usr/bin/env bash
# Runs an xcodebuild command, keeps the full log, and on failure prints a clean list of compiler
# errors to the job log and the run summary (so they're easy to read from a phone).
#   scripts/ci/xcodebuild_step.sh <log-name> xcodebuild <args...>
set -uo pipefail
name="$1"; shift
mkdir -p build/logs
log="build/logs/${name}.log"

"$@" > "$log" 2>&1
status=$?

grep -E "^\*\* .* (SUCCEEDED|FAILED) \*\*" "$log" | tail -2 || true
if [ $status -ne 0 ]; then
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
