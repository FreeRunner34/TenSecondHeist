"""Emit a stable, checked-in Xcode project without requiring XcodeGen."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "TenSecondHeist.xcodeproj"
PROJECT.mkdir(exist_ok=True)
objects = {}


class Ref(str): pass
def uid(key): return Ref(hashlib.sha1(key.encode()).hexdigest()[:24].upper())
def put(key, value):
    identifier = uid(key)
    objects[identifier] = value
    return identifier
def encoded(value):
    if isinstance(value, Ref): return str(value)
    if isinstance(value, str):
        return value if re.fullmatch(r"[A-Za-z0-9_.$/+\-]+", value) else json.dumps(value)
    if isinstance(value, list): return "(" + ", ".join(encoded(v) for v in value) + ")"
    if isinstance(value, dict):
        return "{\n" + "\n".join(f"  {encoded(str(k))} = {encoded(v)};" for k, v in value.items()) + "\n}"
    return str(value)


def group(name, path, children):
    return put("group:" + name, {"isa": "PBXGroup", "children": children,
                                  **({"path": path} if path else {"name": name}), "sourceTree": "<group>"})


def file(name, kind, source="<group>"):
    return put("file:" + name, {"isa": "PBXFileReference", "lastKnownFileType": kind,
                                "path": name, "sourceTree": source})


app_sources = ["TenSecondHeistApp.swift", "HeistScreen.swift", "Visuals.swift", "ReplayExporter.swift", "Soundscape.swift"]
core_sources = ["GameModel.swift", "Simulation.swift", "ProgressStore.swift", "PurchaseManager.swift"]
app_files = [file(name, "sourcecode.swift") for name in app_sources]
core_files = [file(name, "sourcecode.swift") for name in core_sources]
assets = file("Assets.xcassets", "folder.assetcatalog")
levels = file("levels.json", "text.json")
storekit = file("Local.storekit", "text")
audio = [file(name + ".wav", "audio.wav") for name in ["music", "go", "success", "caught"]]
info = put("file:Info.plist", {"isa": "PBXFileReference", "lastKnownFileType": "text.plist.xml",
                               "path": "TenSecondHeist/Info.plist", "sourceTree": "<group>"})
test = file("CampaignTests.swift", "sourcecode.swift")
product_app = put("product:app", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application",
                                  "includeInIndex": 0, "path": "TenSecondHeist.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
product_test = put("product:test", {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle",
                                    "includeInIndex": 0, "path": "TenSecondHeistTests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})
app_group = group("App", "TenSecondHeist/App", app_files)
core_group = group("Core", "TenSecondHeist/Core", core_files)
resource_group = group("Resources", "TenSecondHeist/Resources", [assets, levels, storekit, *audio])
test_group = group("Tests", "TenSecondHeistTests", [test])
products = group("Products", None, [product_app, product_test])
main_group = group("Main", None, [app_group, core_group, resource_group, info, test_group, products])


def build(file_id, key): return put("build:" + key, {"isa": "PBXBuildFile", "fileRef": file_id})
app_source_builds = [build(f, "app:" + n) for f, n in zip(app_files + core_files, app_sources + core_sources)]
test_source_build = build(test, "test:CampaignTests.swift")
app_resource_builds = [build(f, "res:" + n) for f, n in zip([assets, levels, *audio],
    ["Assets.xcassets", "levels.json", "music.wav", "go.wav", "success.wav", "caught.wav"])]
test_resource_build = build(levels, "test:levels.json")


def phase(name, kind, files):
    return put("phase:" + name, {"isa": kind, "buildActionMask": 2147483647,
                                 "files": files, "runOnlyForDeploymentPostprocessing": 0})
app_sources_phase = phase("app-sources", "PBXSourcesBuildPhase", app_source_builds)
app_resources_phase = phase("app-resources", "PBXResourcesBuildPhase", app_resource_builds)
test_sources_phase = phase("test-sources", "PBXSourcesBuildPhase", [test_source_build])
test_resources_phase = phase("test-resources", "PBXResourcesBuildPhase", [test_resource_build])


def config(name, owner, settings):
    return put(f"config:{owner}:{name}", {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": name})
def config_list(owner, debug, release):
    return put("config-list:" + owner, {"isa": "XCConfigurationList",
         "buildConfigurations": [debug, release], "defaultConfigurationIsVisible": 0,
         "defaultConfigurationName": "Release"})


project_common = {"ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
                  "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
                  "SWIFT_VERSION": "5.0", "TARGETED_DEVICE_FAMILY": "1"}
proj_debug = config("Debug", "project", {**project_common, "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"})
proj_release = config("Release", "project", {**project_common, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_COMPILATION_MODE": "wholemodule"})
project_config = config_list("project", proj_debug, proj_release)


app_common = {"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGN_STYLE": "Automatic",
              "CURRENT_PROJECT_VERSION": "1", "INFOPLIST_FILE": "TenSecondHeist/Info.plist",
              "GENERATE_INFOPLIST_FILE": "NO", "MARKETING_VERSION": "1.0",
              "PRODUCT_BUNDLE_IDENTIFIER": "com.revpointstudios.tensecondheist",
              "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_EMIT_LOC_STRINGS": "YES",
              "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "ENABLE_PREVIEWS": "YES"}
app_debug = config("Debug", "app", app_common)
app_release = config("Release", "app", app_common)
app_configs = config_list("app", app_debug, app_release)
test_common = {"BUNDLE_LOADER": "$(TEST_HOST)", "CODE_SIGN_STYLE": "Automatic",
               "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "com.revpointstudios.tensecondheist.tests",
               "PRODUCT_NAME": "$(TARGET_NAME)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/TenSecondHeist.app/TenSecondHeist"}
test_debug = config("Debug", "test", test_common)
test_release = config("Release", "test", test_common)
test_configs = config_list("test", test_debug, test_release)

app_target = uid("target:app")
test_target = uid("target:test")
proxy = put("dependency-proxy", {"isa": "PBXContainerItemProxy", "containerPortal": uid("project"),
    "proxyType": 1, "remoteGlobalIDString": app_target, "remoteInfo": "TenSecondHeist"})
dependency = put("dependency", {"isa": "PBXTargetDependency", "target": app_target, "targetProxy": proxy})
objects[app_target] = {"isa": "PBXNativeTarget", "buildConfigurationList": app_configs,
                       "buildPhases": [app_sources_phase, app_resources_phase], "buildRules": [],
                       "dependencies": [], "name": "TenSecondHeist", "productName": "TenSecondHeist",
                       "productReference": product_app, "productType": "com.apple.product-type.application"}
objects[test_target] = {"isa": "PBXNativeTarget", "buildConfigurationList": test_configs,
                        "buildPhases": [test_sources_phase, test_resources_phase], "buildRules": [],
                        "dependencies": [dependency], "name": "TenSecondHeistTests",
                        "productName": "TenSecondHeistTests", "productReference": product_test,
                        "productType": "com.apple.product-type.bundle.unit-test"}
objects[uid("project")] = {"isa": "PBXProject", "attributes": {"LastUpgradeCheck": "1600",
    "TargetAttributes": {str(app_target): {"CreatedOnToolsVersion": "16.0"},
                         str(test_target): {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}},
    "buildConfigurationList": project_config, "compatibilityVersion": "Xcode 15.0",
    "developmentRegion": "en", "hasScannedForEncodings": 0, "knownRegions": ["en", "Base"],
    "mainGroup": main_group, "productRefGroup": products, "projectDirPath": "", "projectRoot": "",
    "targets": [app_target, test_target]}

body = "// !$*UTF8*$!\n" + encoded({"archiveVersion": 1, "classes": {}, "objectVersion": 60,
    "objects": {str(k): v for k, v in sorted(objects.items())}, "rootObject": uid("project")}) + "\n"
(PROJECT / "project.pbxproj").write_text(body)

scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "TenSecondHeist.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TenSecondHeist.app" BlueprintName="TenSecondHeist" ReferencedContainer="container:TenSecondHeist.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.Posix">
    <Testables>
      <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="TenSecondHeistTests.xctest" BlueprintName="TenSecondHeistTests" ReferencedContainer="container:TenSecondHeist.xcodeproj"/></TestableReference>
    </Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TenSecondHeist.app" BlueprintName="TenSecondHeist" ReferencedContainer="container:TenSecondHeist.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="TenSecondHeist.app" BlueprintName="TenSecondHeist" ReferencedContainer="container:TenSecondHeist.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated TenSecondHeist.xcodeproj")
