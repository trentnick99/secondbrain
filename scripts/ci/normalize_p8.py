#!/usr/bin/env python3
"""Writes a clean PEM key file from the ASC_KEY_P8 secret. Usage: normalize_p8.py <output-path>"""
import base64
import os
import re
import sys
import textwrap

DASH = "[-‐‑‒–—−]"
PATTERN = re.compile(DASH + r"+\s*BEGIN\s+PRIVATE\s+KEY\s*" + DASH + r"+(.*?)" + DASH + r"+\s*END\s+PRIVATE\s+KEY\s*" + DASH + "+", re.S)


def body_of(text: str):
    match = PATTERN.search(text)
    return re.sub(r"[^A-Za-z0-9+/=]", "", match.group(1)) if match else None


raw = os.environ.get("ASC_KEY_P8", "")
body = body_of(raw)
if body is None:
    try:  # the whole .p8 file, base64-encoded
        body = body_of(base64.b64decode(re.sub(r"\s", "", raw)).decode("utf-8", "ignore"))
    except Exception:
        body = None
if body is None:  # just the key lines, without the BEGIN/END markers
    body = re.sub(r"[^A-Za-z0-9+/=]", "", raw)

with open(sys.argv[1], "w") as out:
    out.write("-----BEGIN PRIVATE KEY-----\n" + "\n".join(textwrap.wrap(body, 64)) + "\n-----END PRIVATE KEY-----\n")
