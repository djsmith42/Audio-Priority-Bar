#!/usr/bin/env python3
"""Writes AudioPriorityBar.xcodeproj/project.pbxproj from the source tree.

Every .m and .h under AudioPriorityBar/ joins the app target and every .m
under AudioPriorityBarTests/ joins the test target, so adding a file only
means running this again.
"""

import hashlib
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_DIR = "AudioPriorityBar"
TEST_DIR = "AudioPriorityBarTests"
MARKETING_VERSION = "2.7.0"


def uid(*parts):
    return hashlib.sha1("/".join(parts).encode()).hexdigest()[:24].upper()


def sources(directory, suffixes):
    base = ROOT / directory
    return sorted(
        str(path.relative_to(base))
        for path in base.rglob("*")
        if path.suffix in suffixes and path.is_file()
    )


def file_type(path):
    return {
        ".m": "sourcecode.c.objc",
        ".h": "sourcecode.c.h",
        ".plist": "text.plist.xml",
    }.get(pathlib.Path(path).suffix, "text")


def quote(value):
    safe = all(c.isascii() and (c.isalnum() or c in "._/") for c in value) and value
    return value if safe else '"' + value.replace('"', '\\"') + '"'


app_sources = sources(APP_DIR, {".m"})
app_headers = sources(APP_DIR, {".h"})
test_sources = sources(TEST_DIR, {".m", ".h"})
test_resources = sorted(
    str(path.relative_to(ROOT / TEST_DIR))
    for path in (ROOT / TEST_DIR / "Fixtures").glob("*.plist")
)

objects = {}
build_files = []


def add(key, body):
    objects[key] = body


def file_ref(group, path, last_known=None):
    key = uid("ref", group, path)
    add(key, {
        "isa": "PBXFileReference",
        "lastKnownFileType": last_known or file_type(path),
        "path": path,
        "sourceTree": "<group>",
    })
    return key


def build_file(phase, ref, comment):
    key = uid("build", phase, ref)
    add(key, {"isa": "PBXBuildFile", "fileRef": ref, "_comment": comment})
    return key


# Groups follow directories so Xcode shows the same tree as Finder.
def group_tree(base, paths, name):
    root = {"children": {}, "files": []}
    for path in paths:
        node = root
        parts = path.split("/")
        for part in parts[:-1]:
            node = node["children"].setdefault(part, {"children": {}, "files": []})
        node["files"].append(path)

    refs = {}

    def emit(node, path, label):
        children = []
        for child_name in sorted(node["children"]):
            children.append(emit(node["children"][child_name], f"{path}/{child_name}", child_name))
        for file_path in sorted(node["files"]):
            ref = file_ref(base, file_path)
            # File references are relative to their group.
            objects[ref]["path"] = file_path.split("/")[-1]
            refs[file_path] = ref
            children.append(ref)
        key = uid("group", base, path)
        add(key, {"isa": "PBXGroup", "children": children, "path": label, "sourceTree": "<group>"})
        return key

    return emit(root, base, name), refs


app_group, app_refs = group_tree(APP_DIR, app_sources + app_headers + ["Info.plist"], APP_DIR)
assets_ref = uid("ref", APP_DIR, "Assets.xcassets")
add(assets_ref, {
    "isa": "PBXFileReference",
    "lastKnownFileType": "folder.assetcatalog",
    "path": "Assets.xcassets",
    "sourceTree": "<group>",
})
objects[app_group]["children"].append(assets_ref)
test_group, test_refs = group_tree(TEST_DIR, test_sources + test_resources, TEST_DIR)

license_ref = uid("ref", "LICENSE")
add(license_ref, {"isa": "PBXFileReference", "lastKnownFileType": "text", "path": "LICENSE", "sourceTree": "<group>"})

frameworks = ["CoreAudio", "IOKit", "Carbon", "ServiceManagement", "QuartzCore"]
framework_refs = {}
for name in frameworks:
    key = uid("framework", name)
    add(key, {
        "isa": "PBXFileReference",
        "lastKnownFileType": "wrapper.framework",
        "name": f"{name}.framework",
        "path": f"System/Library/Frameworks/{name}.framework",
        "sourceTree": "SDKROOT",
    })
    framework_refs[name] = key
frameworks_group = uid("group", "Frameworks")
add(frameworks_group, {"isa": "PBXGroup", "children": list(framework_refs.values()), "name": "Frameworks", "sourceTree": "<group>"})

app_product = uid("product", "app")
add(app_product, {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.application",
    "includeInIndex": "0",
    "path": "AudioPriorityBar.app",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
test_product = uid("product", "tests")
add(test_product, {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.cfbundle",
    "includeInIndex": "0",
    "path": "AudioPriorityBarTests.xctest",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
products_group = uid("group", "Products")
add(products_group, {"isa": "PBXGroup", "children": [app_product, test_product], "name": "Products", "sourceTree": "<group>"})

main_group = uid("group", "main")
add(main_group, {
    "isa": "PBXGroup",
    "children": [app_group, test_group, frameworks_group, products_group, license_ref],
    "sourceTree": "<group>",
})

# Sparkle, the one remaining dependency, is an Objective-C framework.
sparkle_package = uid("package", "Sparkle")
add(sparkle_package, {
    "isa": "XCRemoteSwiftPackageReference",
    "repositoryURL": "https://github.com/sparkle-project/Sparkle",
    "requirement": {"kind": "upToNextMajorVersion", "minimumVersion": "2.10.0"},
})
sparkle_product = uid("product-dependency", "Sparkle")
add(sparkle_product, {"isa": "XCSwiftPackageProductDependency", "package": sparkle_package, "productName": "Sparkle"})
sparkle_build = uid("build", "sparkle")
add(sparkle_build, {"isa": "PBXBuildFile", "productRef": sparkle_product})

# Build phases
app_sources_phase = uid("phase", "app-sources")
add(app_sources_phase, {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [build_file("app-sources", app_refs[path], path) for path in app_sources],
    "runOnlyForDeploymentPostprocessing": "0",
})
app_frameworks_phase = uid("phase", "app-frameworks")
add(app_frameworks_phase, {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": "2147483647",
    "files": [build_file("app-frameworks", ref, name) for name, ref in framework_refs.items()] + [sparkle_build],
    "runOnlyForDeploymentPostprocessing": "0",
})
app_resources_phase = uid("phase", "app-resources")
add(app_resources_phase, {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [build_file("app-resources", assets_ref, "Assets"), build_file("app-resources", license_ref, "LICENSE")],
    "runOnlyForDeploymentPostprocessing": "0",
})
test_sources_phase = uid("phase", "test-sources")
add(test_sources_phase, {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [build_file("test-sources", test_refs[path], path) for path in test_sources if path.endswith(".m")],
    "runOnlyForDeploymentPostprocessing": "0",
})
test_frameworks_phase = uid("phase", "test-frameworks")
add(test_frameworks_phase, {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": "2147483647",
    "files": [],
    "runOnlyForDeploymentPostprocessing": "0",
})
test_resources_phase = uid("phase", "test-resources")
add(test_resources_phase, {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [build_file("test-resources", test_refs[path], path) for path in test_resources],
    "runOnlyForDeploymentPostprocessing": "0",
})

app_header_paths = sorted({f"$(SRCROOT)/{APP_DIR}/{pathlib.Path(p).parent}" for p in app_headers})

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "NO",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "macosx",
}


def config(name, settings):
    key = uid("config", name)
    add(key, {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": name.split("/")[-1]})
    return key


def config_list(name, debug, release):
    key = uid("config-list", name)
    add(key, {
        "isa": "XCConfigurationList",
        "buildConfigurations": [debug, release],
        "defaultConfigurationIsVisible": "0",
        "defaultConfigurationName": "Release",
    })
    return key


project_configs = config_list(
    "project",
    config("project/Debug", {
        **common,
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "ONLY_ACTIVE_ARCH": "YES",
    }),
    config("project/Release", {
        **common,
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
    }),
)

app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "GENERATE_INFOPLIST_FILE": "NO",
    "HEADER_SEARCH_PATHS": ["$(inherited)"] + app_header_paths,
    "INFOPLIST_FILE": f"{APP_DIR}/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": "app.audioprioritybar",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SPARKLE_FEED_URL": "",
}
app_configs = config_list("app", config("app/Debug", dict(app_settings)), config("app/Release", dict(app_settings)))

test_settings = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "GENERATE_INFOPLIST_FILE": "YES",
    "HEADER_SEARCH_PATHS": ["$(inherited)"] + app_header_paths,
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "app.audioprioritybar.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/AudioPriorityBar.app/Contents/MacOS/AudioPriorityBar",
}
test_configs = config_list("tests", config("tests/Debug", dict(test_settings)), config("tests/Release", dict(test_settings)))

app_target = uid("target", "app")
test_target = uid("target", "tests")
project = uid("project")
proxy = uid("proxy")
add(proxy, {
    "isa": "PBXContainerItemProxy",
    "containerPortal": project,
    "proxyType": "1",
    "remoteGlobalIDString": app_target,
    "remoteInfo": "AudioPriorityBar",
})
dependency = uid("dependency")
add(dependency, {"isa": "PBXTargetDependency", "target": app_target, "targetProxy": proxy})

add(app_target, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": app_configs,
    "buildPhases": [app_sources_phase, app_frameworks_phase, app_resources_phase],
    "buildRules": [],
    "dependencies": [],
    "name": "AudioPriorityBar",
    "packageProductDependencies": [sparkle_product],
    "productName": "AudioPriorityBar",
    "productReference": app_product,
    "productType": "com.apple.product-type.application",
})
add(test_target, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": test_configs,
    "buildPhases": [test_sources_phase, test_frameworks_phase, test_resources_phase],
    "buildRules": [],
    "dependencies": [dependency],
    "name": "AudioPriorityBarTests",
    "productName": "AudioPriorityBarTests",
    "productReference": test_product,
    "productType": "com.apple.product-type.bundle.unit-test",
})
add(project, {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastUpgradeCheck": "1600",
        "TargetAttributes": {
            app_target: {"CreatedOnToolsVersion": "16.0"},
            test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target},
        },
    },
    "buildConfigurationList": project_configs,
    "compatibilityVersion": "Xcode 14.0",
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base"],
    "mainGroup": main_group,
    "packageReferences": [sparkle_package],
    "productRefGroup": products_group,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [app_target, test_target],
})


def render(value, indent):
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            if key == "_comment":
                continue
            lines.append(f"{pad}\t{quote(key)} = {render(item, indent + 1)};")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines = ["("]
        for item in value:
            lines.append(f"{pad}\t{render(item, indent + 1)},")
        lines.append(pad + ")")
        return "\n".join(lines)
    return quote(str(value))


order = [
    "PBXBuildFile", "PBXContainerItemProxy", "PBXFileReference", "PBXFrameworksBuildPhase",
    "PBXGroup", "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase",
    "PBXTargetDependency", "XCBuildConfiguration", "XCConfigurationList",
    "XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency",
]
out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
for isa in order:
    keys = sorted(k for k, v in objects.items() if v["isa"] == isa)
    if not keys:
        continue
    out.append(f"\n/* Begin {isa} section */")
    for key in keys:
        out.append(f"\t\t{key} = {render(objects[key], 2)};")
    out.append(f"/* End {isa} section */")
out += ["\t};", f"\trootObject = {project};", "}", ""]

target = ROOT / "AudioPriorityBar.xcodeproj" / "project.pbxproj"
target.write_text("\n".join(out))

scheme = ROOT / "AudioPriorityBar.xcodeproj" / "xcshareddata" / "xcschemes" / "AudioPriorityBar.xcscheme"
text = scheme.read_text()
for name, identifier in (("AudioPriorityBar", app_target), ("AudioPriorityBarTests", test_target)):
    text = re.sub(
        r'BlueprintIdentifier = "[^"]*"(\s*BuildableName = "[^"]*"\s*BlueprintName = "' + name + '")',
        f'BlueprintIdentifier = "{identifier}"\\1',
        text,
    )
scheme.write_text(text)
print(f"Wrote {target.relative_to(ROOT)}: {len(app_sources)} app sources, {len([p for p in test_sources if p.endswith('.m')])} test sources")
