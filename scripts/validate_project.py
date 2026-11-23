#!/usr/bin/env python3
"""Validates the generated Xcode project without Xcode: parses project.pbxproj (OpenStep plist),
checks every object reference resolves, checks schemes / plists are well-formed, and confirms each
synchronized folder exists. Run: python3 scripts/validate_project.py"""
import glob
import os
import plistlib
import re
import sys
import xml.dom.minidom

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)


class Parser:
    """Minimal OpenStep property-list parser (the format of project.pbxproj)."""

    def __init__(self, text):
        self.s = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        self.s = re.sub(r"^//.*$", "", self.s, flags=re.M)
        self.i = 0

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.dict()
        if c == "(":
            return self.array()
        if c == '"':
            return self.quoted()
        m = re.compile(r"[A-Za-z0-9_$./:@+-]+").match(self.s, self.i)
        if not m:
            raise ValueError(f"Unexpected token at {self.i}: {self.s[self.i:self.i + 30]!r}")
        self.i = m.end()
        return m.group(0)

    def quoted(self):
        self.i += 1
        out = []
        while self.s[self.i] != '"':
            if self.s[self.i] == "\\":
                self.i += 1
            out.append(self.s[self.i])
            self.i += 1
        self.i += 1
        return "".join(out)

    def expect(self, ch):
        self.ws()
        if self.s[self.i] != ch:
            raise ValueError(f"Expected {ch!r} at {self.i}: {self.s[self.i:self.i + 40]!r}")
        self.i += 1

    def dict(self):
        self.expect("{")
        d = {}
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return d
            key = self.value()
            self.expect("=")
            d[key] = self.value()
            self.expect(";")

    def array(self):
        self.expect("(")
        a = []
        while True:
            self.ws()
            if self.s[self.i] == ")":
                self.i += 1
                return a
            a.append(self.value())
            self.ws()
            if self.s[self.i] == ",":
                self.i += 1


problems = []
text = open("SecondBrain.xcodeproj/project.pbxproj").read()
root = Parser(text).dict()
objects = root["objects"]
print(f"project.pbxproj parsed: objectVersion {root['objectVersion']}, {len(objects)} objects")

refs = set(re.findall(r"\b[0-9A-F]{24}\b", text))
dangling = sorted(r for r in refs if r not in objects)
if dangling:
    problems.append(f"Dangling references: {dangling}")
if root["rootObject"] not in objects:
    problems.append("rootObject missing")

for oid, obj in objects.items():
    isa = obj["isa"]
    if isa == "PBXFileSystemSynchronizedRootGroup":
        parent = next((o for o in objects.values() if o["isa"] == "PBXGroup" and oid in o.get("children", [])), None)
        base = parent.get("path", "") if parent else ""
        path = os.path.join(base, obj["path"])
        if not os.path.isdir(path):
            problems.append(f"Synchronized folder missing: {path}")
    if isa == "PBXFileReference" and obj.get("sourceTree") == "<group>":
        parent = next((o for o in objects.values() if o["isa"] == "PBXGroup" and oid in o.get("children", [])), None)
        base = parent.get("path", "") if parent else ""
        path = os.path.join(base, obj["path"])
        if not os.path.exists(path):
            problems.append(f"File reference missing on disk: {path}")

for t in (o for o in objects.values() if o["isa"] == "PBXNativeTarget"):
    print(f"  target {t['name']:<20} {t['productType']:<45} sync folders: {len(t.get('fileSystemSynchronizedGroups', []))}")
    for cfg_id in objects[t["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[cfg_id]["buildSettings"]
        for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
            if key in settings and not os.path.exists(settings[key]):
                problems.append(f"{t['name']}: {key} points to missing {settings[key]}")

for f in glob.glob("SecondBrain.xcodeproj/**/*.xcscheme", recursive=True) + glob.glob("SecondBrain.xcodeproj/**/*.xcworkspacedata", recursive=True):
    xml.dom.minidom.parse(f)
    for bid in re.findall(r'BlueprintIdentifier = "([0-9A-F]{24})"', open(f).read()):
        if bid not in objects:
            problems.append(f"{f}: unknown BlueprintIdentifier {bid}")
    print(f"  xml ok: {f}")

for f in glob.glob("Config/*.plist") + glob.glob("Config/*.entitlements"):
    plistlib.load(open(f, "rb"))
    print(f"  plist ok: {f}")

import json
for f in glob.glob("App/Resources/Assets.xcassets/**/Contents.json", recursive=True):
    json.load(open(f))
print("  asset catalog JSON ok")

if not os.path.exists("Packages/SecondBrainCore/Package.swift"):
    problems.append("Local package missing")

if problems:
    print("\nPROBLEMS:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("\nProject structure valid.")
