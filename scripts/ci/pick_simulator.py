#!/usr/bin/env python3
"""Reads `xcrun simctl list devices available --json` on stdin and prints the UDID of an iPhone
simulator on the newest installed iOS runtime (the name goes to stderr for the log)."""
import json
import re
import sys

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in items:
        if not device.get("isAvailable", True) or not device["name"].startswith("iPhone"):
            continue
        # Prefer the newest runtime, then a non-"Pro Max"/"Plus" model (faster to boot, standard size).
        preference = 0 if not any(word in device["name"] for word in ("Max", "Plus", "Air")) else 1
        key = (version, -preference)
        if best is None or key > best[0]:
            best = (key, device["udid"], device["name"], runtime)

if best is None:
    sys.exit("No available iPhone simulator found")
print(f"Using {best[2]} ({best[3]})", file=sys.stderr)
print(best[1])
