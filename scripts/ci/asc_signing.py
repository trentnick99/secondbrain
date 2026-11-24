#!/usr/bin/env python3
"""App Store signing without a Mac or a registered iPhone.

Uses the App Store Connect API key to create an Apple Distribution certificate (private key made on the
runner, never stored) and App Store provisioning profiles for the app and widget, then installs them in a
temporary keychain. Usage:

    asc_signing.py setup     # writes SB_PROFILE_*, SB_KEYCHAIN and SB_KEYCHAIN_PASSWORD to $GITHUB_ENV
    asc_signing.py cleanup   # deletes this run's profiles and the temporary keychain

Reads ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, BUILD_NUMBER and RUNNER_TEMP. Older
certificates that this workflow made are revoked only when Apple's certificate limit is reached; builds
already uploaded to TestFlight aren't affected by revoking a distribution certificate.
"""
import base64
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_PREFIX = "SecondBrain CI"
TEMP = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
STATE = TEMP / "asc_signing_state.json"


def fail(message):
    print(f"::error::{message}")
    with open(os.environ.get("GITHUB_STEP_SUMMARY", os.devnull), "a") as summary:
        summary.write(f"### ❌ Signing setup\n{message}\n")
    sys.exit(1)


def token():
    pem = Path(os.environ["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      pem, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except Exception:
            return error.code, {"errors": [{"detail": raw.decode("utf-8", "ignore")[:300]}]}


def describe(body):
    return "; ".join(f"{e.get('title', '')} {e.get('detail', '')}".strip() for e in body.get("errors", [])) or "no details"


def run(*args, check=True):
    return subprocess.run(list(args), check=check, capture_output=True, text=True)


def env_out(name, value, mask=False):
    if mask:
        print(f"::add-mask::{value}")
    with open(os.environ["GITHUB_ENV"], "a") as env:
        env.write(f"{name}={value}\n")


def create_certificate():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Second Brain CI"),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "US")]))
           .sign(key, hashes.SHA256()))
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    body = {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem}}}

    status, response = call("POST", "/certificates", body)
    if status == 409 or (status >= 400 and "limit" in describe(response).lower()) or (
            status >= 400 and "already have" in describe(response).lower()):
        # Apple's limit on distribution certificates: revoke the oldest ones and try again.
        print("Distribution certificate limit reached — revoking older certificates made by this workflow.")
        _, listing = call("GET", "/certificates?filter%5BcertificateType%5D=DISTRIBUTION,IOS_DISTRIBUTION&limit=50")
        certs = sorted(listing.get("data", []), key=lambda c: c["attributes"].get("expirationDate", ""))
        for cert in certs[:-1] if len(certs) > 1 else certs:
            call("DELETE", f"/certificates/{cert['id']}")
        status, response = call("POST", "/certificates", body)
    if status >= 400:
        fail(f"Apple wouldn't create a distribution certificate ({status}): {describe(response)}. "
             "If it mentions a limit, revoke old Distribution certificates in Certificates, Identifiers & Profiles › Certificates.")

    cert_id = response["data"]["id"]
    cert_der = base64.b64decode(response["data"]["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(cert_der)
    p12_password = secrets.token_urlsafe(18)
    p12 = pkcs12.serialize_key_and_certificates(b"SecondBrain CI", key, certificate, None,
                                                serialization.BestAvailableEncryption(p12_password.encode()))
    p12_path = TEMP / "dist.p12"
    p12_path.write_bytes(p12)
    return cert_id, p12_path, p12_password


def install_keychain(p12_path, p12_password):
    keychain = str(TEMP / "secondbrain-signing.keychain-db")
    password = secrets.token_urlsafe(18)
    run("security", "create-keychain", "-p", password, keychain)
    run("security", "set-keychain-settings", "-lut", "21600", keychain)
    run("security", "unlock-keychain", "-p", password, keychain)
    wwdr = TEMP / "AppleWWDRCAG3.cer"
    try:
        urllib.request.urlretrieve("https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer", wwdr)
        run("security", "import", str(wwdr), "-k", keychain, "-T", "/usr/bin/codesign", check=False)
    except Exception:
        print("Couldn't download the Apple WWDR intermediate; relying on the system keychain.")
    run("security", "import", str(p12_path), "-k", keychain, "-P", p12_password, "-f", "pkcs12",
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", "-T", "/usr/bin/productbuild")
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    existing = run("security", "list-keychains", "-d", "user").stdout.split()
    existing = [k.strip().strip('"') for k in existing]
    run("security", "list-keychains", "-d", "user", "-s", keychain, *[k for k in existing if k != keychain])
    p12_path.unlink(missing_ok=True)
    identities = run("security", "find-identity", "-v", "-p", "codesigning", keychain).stdout
    print("Signing identities in the temporary keychain:\n" + "\n".join(
        line.split('"')[1] if '"' in line else line for line in identities.splitlines()))
    return keychain, password


def bundle_resource_id(identifier):
    status, response = call("GET", "/bundleIds?" + urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 200}))
    if status >= 400:
        fail(f"Couldn't look up the App ID {identifier} ({status}): {describe(response)}")
    for item in response.get("data", []):
        if item["attributes"].get("identifier") == identifier:
            return item["id"]
    fail(f"There's no App ID {identifier} in Certificates, Identifiers & Profiles › Identifiers. Register it (with App Groups) and run again.")


def create_profile(identifier, bundle_id, cert_id, build):
    # Remove this workflow's older profiles for the same App ID so they don't pile up.
    _, listing = call("GET", "/profiles?" + urllib.parse.urlencode({"filter[name]": f"{PROFILE_PREFIX} {identifier}", "limit": 200}))
    for profile in listing.get("data", []):
        if profile["attributes"].get("name", "").startswith(f"{PROFILE_PREFIX} {identifier}"):
            call("DELETE", f"/profiles/{profile['id']}")
    name = f"{PROFILE_PREFIX} {identifier} {build}"
    body = {"data": {"type": "profiles",
                     "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                     "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                                       "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}}
    status, response = call("POST", "/profiles", body)
    if status >= 400:
        fail(f"Apple wouldn't create the App Store profile for {identifier} ({status}): {describe(response)}")
    attributes = response["data"]["attributes"]
    content = base64.b64decode(attributes["profileContent"])
    uuid = attributes["uuid"]
    for folder in (Path.home() / "Library/MobileDevice/Provisioning Profiles",
                   Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{uuid}.mobileprovision").write_bytes(content)
    return response["data"]["id"], name


def setup():
    bundle = os.environ["BUNDLE_ID"]
    build = os.environ.get("BUILD_NUMBER", "0")
    cert_id, p12_path, p12_password = create_certificate()
    keychain, keychain_password = install_keychain(p12_path, p12_password)
    app_profile_id, app_profile = create_profile(bundle, bundle_resource_id(bundle), cert_id, build)
    widget = f"{bundle}.widgets"
    widget_profile_id, widget_profile = create_profile(widget, bundle_resource_id(widget), cert_id, build)
    STATE.write_text(json.dumps({"keychain": keychain, "profiles": [app_profile_id, widget_profile_id]}))
    env_out("SB_PROFILE_APP", app_profile)
    env_out("SB_PROFILE_WIDGETS", widget_profile)
    env_out("SB_KEYCHAIN", keychain)
    env_out("SB_KEYCHAIN_PASSWORD", keychain_password, mask=True)
    print(f"Created App Store profiles “{app_profile}” and “{widget_profile}”.")


def cleanup():
    if not STATE.exists():
        return
    state = json.loads(STATE.read_text())
    run("security", "delete-keychain", state.get("keychain", ""), check=False)
    STATE.unlink(missing_ok=True)


if __name__ == "__main__":
    {"setup": setup, "cleanup": cleanup}[sys.argv[1]]()
