#!/usr/bin/env python3
"""Generates SecondBrain.xcodeproj deterministically.

Uses Xcode 16+ file-system-synchronized folders, so any Swift file added under App/, Shared/,
Widgets/ or Tests/ is picked up automatically without editing the project.

    python3 scripts/generate_xcodeproj.py
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ = os.path.join(ROOT, "SecondBrain.xcodeproj")


def oid(name: str) -> str:
    return hashlib.md5(("SecondBrain:" + name).encode()).hexdigest()[:24].upper()


SAFE = re.compile(r"^[A-Za-z0-9_$./]+$")


def q(value) -> str:
    s = str(value)
    if s and SAFE.match(s) and not s.startswith("//"):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def ser(value, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for k, v in value.items():
            lines.append(f"{pad}\t{q(k)} = {ser(v, indent + 1)};")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "(\n" + pad + ")"
        lines = ["("]
        for v in value:
            lines.append(f"{pad}\t{ser(v, indent + 1)},")
        lines.append(pad + ")")
        return "\n".join(lines)
    return q(value)


objects = {}


def add(name, obj):
    objects[oid(name)] = obj
    return oid(name)


# ── IDs ──────────────────────────────────────────────────────────────────────
PROJECT = oid("project")
MAIN_GROUP = oid("group.main")
PRODUCTS_GROUP = oid("group.products")
CONFIG_GROUP = oid("group.config")
TESTS_GROUP = oid("group.tests")

T_APP, T_WID, T_UNIT, T_UI = oid("target.app"), oid("target.widgets"), oid("target.unit"), oid("target.ui")
P_APP, P_WID, P_UNIT, P_UI = oid("product.app"), oid("product.widgets"), oid("product.unit"), oid("product.ui")
T_WATCH, P_WATCH = oid("target.watch"), oid("product.watch")

# ── File references ─────────────────────────────────────────────────────────
add("product.app", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
                    "path": "SecondBrain.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
add("product.widgets", {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension", "includeInIndex": "0",
                        "path": "SecondBrainWidgets.appex", "sourceTree": "BUILT_PRODUCTS_DIR"})
add("product.watch", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": "0",
                      "path": "SecondBrainWatch.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
add("product.unit", {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "includeInIndex": "0",
                     "path": "SecondBrainTests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})
add("product.ui", {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "includeInIndex": "0",
                   "path": "SecondBrainUITests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})

config_files = [
    ("Signing.xcconfig", "text.xcconfig"),
    ("SecondBrain-Info.plist", "text.plist.xml"),
    ("SecondBrainWidgets-Info.plist", "text.plist.xml"),
    ("SecondBrain.entitlements", "text.plist.entitlements"),
    ("SecondBrainWidgets.entitlements", "text.plist.entitlements"),
]
config_refs = []
for name, ftype in config_files:
    config_refs.append(add("config." + name, {"isa": "PBXFileReference", "lastKnownFileType": ftype,
                                              "path": name, "sourceTree": "<group>"}))
XCCONFIG = oid("config.Signing.xcconfig")

# Local Swift package (folder reference — Xcode resolves it as a package).
PKG_REF = add("package.core", {"isa": "PBXFileReference", "lastKnownFileType": "wrapper", "name": "SecondBrainCore",
                               "path": "Packages/SecondBrainCore", "sourceTree": "<group>"})

README_REF = add("file.readme", {"isa": "PBXFileReference", "lastKnownFileType": "net.daringfireball.markdown",
                                 "path": "README.md", "sourceTree": "<group>"})

# ── Synchronized folders ────────────────────────────────────────────────────
G_APP = add("sync.app", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "App", "sourceTree": "<group>"})
G_SHARED = add("sync.shared", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Shared", "sourceTree": "<group>"})
G_WIDGETS = add("sync.widgets", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Widgets", "sourceTree": "<group>"})
G_WATCH = add("sync.watch", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Watch", "sourceTree": "<group>"})
G_UNIT = add("sync.unit", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "UnitTests", "sourceTree": "<group>"})
G_UI = add("sync.ui", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "UITests", "sourceTree": "<group>"})
G_DOCS = add("sync.docs", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Docs", "sourceTree": "<group>"})

# ── Groups ──────────────────────────────────────────────────────────────────
add("group.config", {"isa": "PBXGroup", "children": config_refs, "path": "Config", "sourceTree": "<group>"})
add("group.tests", {"isa": "PBXGroup", "children": [G_UNIT, G_UI], "path": "Tests", "sourceTree": "<group>"})
add("group.products", {"isa": "PBXGroup", "children": [P_APP, P_WID, P_WATCH, P_UNIT, P_UI], "name": "Products", "sourceTree": "<group>"})
add("group.main", {"isa": "PBXGroup",
                   "children": [README_REF, G_APP, G_SHARED, G_WIDGETS, G_WATCH, PKG_REF, TESTS_GROUP, CONFIG_GROUP, G_DOCS, PRODUCTS_GROUP],
                   "sourceTree": "<group>"})

# ── Package product dependencies ────────────────────────────────────────────
PD_APP = add("pkgdep.app", {"isa": "XCSwiftPackageProductDependency", "productName": "SecondBrainCore"})
PD_WID = add("pkgdep.widgets", {"isa": "XCSwiftPackageProductDependency", "productName": "SecondBrainCore"})
BF_APP_CORE = add("bf.app.core", {"isa": "PBXBuildFile", "productRef": PD_APP})
BF_WID_CORE = add("bf.widgets.core", {"isa": "PBXBuildFile", "productRef": PD_WID})
BF_EMBED = add("bf.embed.widgets", {"isa": "PBXBuildFile", "fileRef": P_WID,
                                     "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
BF_EMBED_WATCH = add("bf.embed.watch", {"isa": "PBXBuildFile", "fileRef": P_WATCH,
                                         "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})

# ── Build phases ────────────────────────────────────────────────────────────
def phase(name, isa, files=None, extra=None):
    obj = {"isa": isa, "buildActionMask": "2147483647", "files": files or [], "runOnlyForDeploymentPostprocessing": "0"}
    if extra:
        obj.update(extra)
    return add(name, obj)


APP_PHASES = [
    phase("phase.app.sources", "PBXSourcesBuildPhase"),
    phase("phase.app.frameworks", "PBXFrameworksBuildPhase", [BF_APP_CORE]),
    phase("phase.app.resources", "PBXResourcesBuildPhase"),
    phase("phase.app.embed", "PBXCopyFilesBuildPhase", [BF_EMBED],
          {"dstPath": "", "dstSubfolderSpec": "13", "name": "Embed Foundation Extensions"}),
    phase("phase.app.embedwatch", "PBXCopyFilesBuildPhase", [BF_EMBED_WATCH],
          {"dstPath": "$(CONTENTS_FOLDER_PATH)/Watch", "dstSubfolderSpec": "16", "name": "Embed Watch Content"}),
]
WATCH_PHASES = [
    phase("phase.watch.sources", "PBXSourcesBuildPhase"),
    phase("phase.watch.frameworks", "PBXFrameworksBuildPhase"),
    phase("phase.watch.resources", "PBXResourcesBuildPhase"),
]
WID_PHASES = [
    phase("phase.wid.sources", "PBXSourcesBuildPhase"),
    phase("phase.wid.frameworks", "PBXFrameworksBuildPhase", [BF_WID_CORE]),
    phase("phase.wid.resources", "PBXResourcesBuildPhase"),
]
UNIT_PHASES = [
    phase("phase.unit.sources", "PBXSourcesBuildPhase"),
    phase("phase.unit.frameworks", "PBXFrameworksBuildPhase"),
    phase("phase.unit.resources", "PBXResourcesBuildPhase"),
]
UI_PHASES = [
    phase("phase.ui.sources", "PBXSourcesBuildPhase"),
    phase("phase.ui.frameworks", "PBXFrameworksBuildPhase"),
    phase("phase.ui.resources", "PBXResourcesBuildPhase"),
]

# ── Dependencies ────────────────────────────────────────────────────────────
def dependency(name, target, remote_name):
    proxy = add(name + ".proxy", {"isa": "PBXContainerItemProxy", "containerPortal": PROJECT, "proxyType": "1",
                                  "remoteGlobalIDString": target, "remoteInfo": remote_name})
    return add(name, {"isa": "PBXTargetDependency", "target": target, "targetProxy": proxy})


TD_WID = dependency("dep.app.widgets", T_WID, "SecondBrainWidgets")
TD_WATCH = dependency("dep.app.watch", T_WATCH, "SecondBrainWatch")
TD_UNIT = dependency("dep.unit.app", T_APP, "SecondBrain")
TD_UI = dependency("dep.ui.app", T_APP, "SecondBrain")

# ── Build settings ──────────────────────────────────────────────────────────
COMMON_PROJECT = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
PROJECT_DEBUG = dict(COMMON_PROJECT, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
PROJECT_RELEASE = dict(COMMON_PROJECT, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

IPHONE_ONLY = {
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
}

APP_SETTINGS = dict(IPHONE_ONLY, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/SecondBrain.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Config/SecondBrain-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    # Apple's on-device model (iOS 26+) is optional; the app still runs on iOS 18.
    "OTHER_LDFLAGS": ["$(inherited)", "-weak_framework", "FoundationModels"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BASE_BUNDLE_ID)",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
})
WID_SETTINGS = dict(IPHONE_ONLY, **{
    "CODE_SIGN_ENTITLEMENTS": "Config/SecondBrainWidgets.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Config/SecondBrainWidgets-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BASE_BUNDLE_ID).widgets",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
})
# The Apple Watch app (watchOS 10+), embedded in the iPhone app.
WATCH_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Coach Spark",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": "$(BASE_BUNDLE_ID)",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BASE_BUNDLE_ID).watchkitapp",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SDKROOT": "watchos",
    "SKIP_INSTALL": "YES",
    "SUPPORTED_PLATFORMS": "watchos watchsimulator",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "4",
    "WATCHOS_DEPLOYMENT_TARGET": "10.0",
}
UNIT_SETTINGS = dict(IPHONE_ONLY, **{
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BASE_BUNDLE_ID).tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/SecondBrain.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SecondBrain",
})
UI_SETTINGS = dict(IPHONE_ONLY, **{
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(BASE_BUNDLE_ID).uitests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TEST_TARGET_NAME": "SecondBrain",
})


def config_list(name, debug, release, base=None):
    def cfg(label, settings):
        obj = {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": label}
        if base:
            obj["baseConfigurationReference"] = base
        return add(f"{name}.{label}", obj)

    return add(name, {"isa": "XCConfigurationList", "buildConfigurations": [cfg("Debug", debug), cfg("Release", release)],
                      "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Release"})


CL_PROJECT = config_list("cl.project", PROJECT_DEBUG, PROJECT_RELEASE, base=XCCONFIG)
# Keep every Core symbol available to the unit-test bundle in Debug.
CL_APP = config_list("cl.app", dict(APP_SETTINGS, DEAD_CODE_STRIPPING="NO"), APP_SETTINGS)
CL_WID = config_list("cl.widgets", WID_SETTINGS, WID_SETTINGS)
CL_WATCH = config_list("cl.watch", WATCH_SETTINGS, WATCH_SETTINGS)
CL_UNIT = config_list("cl.unit", UNIT_SETTINGS, UNIT_SETTINGS)
CL_UI = config_list("cl.ui", UI_SETTINGS, UI_SETTINGS)

# ── Targets ─────────────────────────────────────────────────────────────────
objects[T_APP] = {"isa": "PBXNativeTarget", "buildConfigurationList": CL_APP, "buildPhases": APP_PHASES, "buildRules": [],
                  "dependencies": [TD_WID, TD_WATCH], "fileSystemSynchronizedGroups": [G_APP, G_SHARED], "name": "SecondBrain",
                  "packageProductDependencies": [PD_APP], "productName": "SecondBrain", "productReference": P_APP,
                  "productType": "com.apple.product-type.application"}
objects[T_WID] = {"isa": "PBXNativeTarget", "buildConfigurationList": CL_WID, "buildPhases": WID_PHASES, "buildRules": [],
                  "dependencies": [], "fileSystemSynchronizedGroups": [G_WIDGETS, G_SHARED], "name": "SecondBrainWidgets",
                  "packageProductDependencies": [PD_WID], "productName": "SecondBrainWidgets", "productReference": P_WID,
                  "productType": "com.apple.product-type.app-extension"}
objects[T_WATCH] = {"isa": "PBXNativeTarget", "buildConfigurationList": CL_WATCH, "buildPhases": WATCH_PHASES, "buildRules": [],
                    "dependencies": [], "fileSystemSynchronizedGroups": [G_WATCH], "name": "SecondBrainWatch",
                    "packageProductDependencies": [], "productName": "SecondBrainWatch", "productReference": P_WATCH,
                    "productType": "com.apple.product-type.application"}
objects[T_UNIT] = {"isa": "PBXNativeTarget", "buildConfigurationList": CL_UNIT, "buildPhases": UNIT_PHASES, "buildRules": [],
                   "dependencies": [TD_UNIT], "fileSystemSynchronizedGroups": [G_UNIT], "name": "SecondBrainTests",
                   "packageProductDependencies": [], "productName": "SecondBrainTests", "productReference": P_UNIT,
                   "productType": "com.apple.product-type.bundle.unit-test"}
objects[T_UI] = {"isa": "PBXNativeTarget", "buildConfigurationList": CL_UI, "buildPhases": UI_PHASES, "buildRules": [],
                 "dependencies": [TD_UI], "fileSystemSynchronizedGroups": [G_UI], "name": "SecondBrainUITests",
                 "packageProductDependencies": [], "productName": "SecondBrainUITests", "productReference": P_UI,
                 "productType": "com.apple.product-type.bundle.ui-testing"}

objects[PROJECT] = {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "1600",
        "LastUpgradeCheck": "1600",
        "TargetAttributes": {
            T_APP: {"CreatedOnToolsVersion": "16.0"},
            T_WID: {"CreatedOnToolsVersion": "16.0"},
            T_WATCH: {"CreatedOnToolsVersion": "16.0"},
            T_UNIT: {"CreatedOnToolsVersion": "16.0", "TestTargetID": T_APP},
            T_UI: {"CreatedOnToolsVersion": "16.0", "TestTargetID": T_APP},
        },
    },
    "buildConfigurationList": CL_PROJECT,
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base"],
    "mainGroup": MAIN_GROUP,
    "minimizedProjectReferenceProxies": "1",
    "preferredProjectObjectVersion": "77",
    "productRefGroup": PRODUCTS_GROUP,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [T_APP, T_WID, T_WATCH, T_UNIT, T_UI],
}

# ── Write project.pbxproj ───────────────────────────────────────────────────
order = ["PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase", "PBXFileReference",
         "PBXFileSystemSynchronizedRootGroup", "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget", "PBXProject",
         "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "PBXTargetDependency", "XCBuildConfiguration",
         "XCConfigurationList", "XCSwiftPackageProductDependency"]
out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 77;", "\tobjects = {"]
for isa in order:
    items = sorted((k, v) for k, v in objects.items() if v["isa"] == isa)
    if not items:
        continue
    out.append("")
    out.append(f"/* Begin {isa} section */")
    for key, obj in items:
        out.append(f"\t\t{key} = {ser(obj, 2)};")
    out.append(f"/* End {isa} section */")
out += ["\t};", f"\trootObject = {PROJECT};", "}", ""]

os.makedirs(PROJ, exist_ok=True)
with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
    f.write("\n".join(out))

# ── Workspace settings & shared scheme ──────────────────────────────────────
ws = os.path.join(PROJ, "project.xcworkspace")
os.makedirs(os.path.join(ws, "xcshareddata"), exist_ok=True)
with open(os.path.join(ws, "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')


def buildable(target_id, product, name, container="container:SecondBrain.xcodeproj"):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "{container}"></BuildableReference>')


app_ref = buildable(T_APP, "SecondBrain.app", "SecondBrain")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES" buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "YES">
            {buildable(T_UNIT, "SecondBrainTests.xctest", "SecondBrainTests")}
         </TestableReference>
         <TestableReference skipped = "NO">
            {buildable(T_UI, "SecondBrainUITests.xctest", "SecondBrainUITests")}
         </TestableReference>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "SecondBrainCoreTests" BuildableName = "SecondBrainCoreTests" BlueprintName = "SecondBrainCoreTests" ReferencedContainer = "container:Packages/SecondBrainCore"></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
schemes = os.path.join(PROJ, "xcshareddata", "xcschemes")
os.makedirs(schemes, exist_ok=True)
with open(os.path.join(schemes, "SecondBrain.xcscheme"), "w") as f:
    f.write(scheme)

widget_ref = buildable(T_WID, "SecondBrainWidgets.appex", "SecondBrainWidgets")
widget_scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" wasCreatedForAppExtension = "YES" version = "2.0">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {widget_ref}
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES"></TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn" launchStyle = "0" askForAppToLaunch = "Yes" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES" launchAutomaticallySubstyle = "2">
      <RemoteRunnable runnableDebuggingMode = "2" BundleIdentifier = "com.apple.springboard">
         {widget_ref}
      </RemoteRunnable>
      <EnvironmentVariables>
         <EnvironmentVariable key = "_XCWidgetKind" value = "" isEnabled = "YES"></EnvironmentVariable>
         <EnvironmentVariable key = "_XCWidgetDefaultView" value = "timeline" isEnabled = "YES"></EnvironmentVariable>
         <EnvironmentVariable key = "_XCWidgetFamily" value = "medium" isEnabled = "YES"></EnvironmentVariable>
      </EnvironmentVariables>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
with open(os.path.join(schemes, "SecondBrainWidgets.xcscheme"), "w") as f:
    f.write(widget_scheme)

print(f"Wrote {PROJ} with {len(objects)} objects")
