#!/usr/bin/env python3
"""Checks the App Store Connect API key before archiving, and says exactly what's wrong.

Never prints the key or the IDs. Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH and BUNDLE_ID
from the environment. Exits non-zero with a plain-language ::error:: when the key can't be used.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def fail(message: str) -> None:
    print(f"::error::{message}")
    with open(os.environ.get("GITHUB_STEP_SUMMARY", os.devnull), "a") as summary:
        summary.write(f"### ❌ API key check\n{message}\n")
    sys.exit(1)


key_id = os.environ.get("ASC_KEY_ID", "")
issuer = os.environ.get("ASC_ISSUER_ID", "")
key_path = os.environ.get("ASC_KEY_PATH", "")
bundle_id = os.environ.get("BUNDLE_ID", "")

problems = []
if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
    problems.append(
        f"ASC_KEY_ID should be the 10-character Key ID (capital letters and digits); it has {len(key_id)} characters"
        + (" and looks like an Issuer ID — the two may be swapped" if re.fullmatch(r"[0-9a-f-]{36}", key_id) else "")
    )
if not re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", issuer):
    problems.append(
        f"ASC_ISSUER_ID should be the Issuer ID shown above the keys list (36 characters with dashes); it has {len(issuer)} characters"
    )
try:
    pem = open(key_path).read()
except OSError:
    pem = ""
if "BEGIN PRIVATE KEY" not in pem or "END PRIVATE KEY" not in pem:
    problems.append("ASC_KEY_P8 must be the whole key file, including the BEGIN PRIVATE KEY and END PRIVATE KEY lines")
if problems:
    fail("; ".join(problems) + ". Update the secret under Settings › Secrets and variables › Actions, then run TestFlight again.")

try:
    import jwt  # PyJWT
except ImportError:
    fail("The key check couldn't load PyJWT on the runner.")

try:
    token = jwt.encode(
        {"iss": issuer, "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
        pem,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
except Exception:
    fail("ASC_KEY_P8 isn't a readable private key. Copy the whole .p8 file again (every line, BEGIN to END) into the secret.")

url = "https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=" + urllib.parse.quote(bundle_id)
request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
        status = response.status
except urllib.error.HTTPError as error:
    status = error.code
    try:
        body = json.load(error)
    except Exception:
        body = {}

codes = [e.get("code", "") for e in body.get("errors", [])]
details = "; ".join(f"{e.get('title', '')} {e.get('detail', '')}".strip() for e in body.get("errors", []))
print(f"App Store Connect API responded {status} {' '.join(codes)}")

if status == 401:
    fail("Apple rejected the API key (401). The Key ID, Issuer ID and key file don't belong together, or the key was revoked. "
         "Check that ASC_KEY_ID is the Key ID from the key's row, ASC_ISSUER_ID is the Issuer ID above the list (a Team key, not an Individual key), "
         "and ASC_KEY_P8 is that same key's .p8 file. If the key file is lost, revoke the key, make a new Admin key and update all three secrets.")
if status == 403:
    if any("AGREEMENT" in c for c in codes):
        fail("Apple needs you to accept an agreement first. Sign in to appstoreconnect.apple.com and developer.apple.com/account, accept any agreement banner, then run again.")
    fail(f"Apple refused the request (403): {details}. The key may need Admin access.")
if status != 200:
    fail(f"App Store Connect API returned {status}: {details}")

apps = body.get("data", [])
if not apps:
    fail(f"The key works, but there's no app in App Store Connect with the bundle ID {bundle_id}. Create it under Apps › + › New App.")
print(f"API key OK — found the App Store Connect app for {bundle_id}.")
with open(os.environ.get("GITHUB_STEP_SUMMARY", os.devnull), "a") as summary:
    summary.write(f"✅ API key works and the App Store Connect app for `{bundle_id}` exists.\n")
