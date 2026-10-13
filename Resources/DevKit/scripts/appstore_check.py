#!/usr/bin/env python3
"""Check local release inputs; external acceptance is never inferred from a build."""

import argparse
import json
import plistlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LANGUAGES = {"en", "de", "es", "fr", "ja", "ko", "zh-Hans"}
PURPOSE = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
COLLECTED_TYPES = {
    "NSPrivacyCollectedDataTypeEmailAddress",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeDeviceID",
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypePhotosorVideos",
}
RELEASE_GATES = {
    "production_sign_in", "account_deletion", "privacy_and_provider_review",
    "signed_archive", "app_store_metadata", "device_acceptance", "testflight_acceptance",
    "gateway_contract_acceptance",
    "compiler_warning_review",
}


def validate_manifest(data):
    errors = []
    expected = {
        "NSPrivacyAccessedAPITypes", "NSPrivacyCollectedDataTypes",
        "NSPrivacyTracking", "NSPrivacyTrackingDomains",
    }
    if set(data) != expected:
        errors.append("Privacy manifest must contain the four supported root keys.")
    if data.get("NSPrivacyTracking") is not False or data.get("NSPrivacyTrackingDomains") != []:
        errors.append("Tracking declaration differs from the current no-tracking product.")
    reasons = {
        item.get("NSPrivacyAccessedAPIType"): item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in data.get("NSPrivacyAccessedAPITypes", [])
    }
    for category, reason in {
        "NSPrivacyAccessedAPICategoryFileTimestamp": "C617.1",
        "NSPrivacyAccessedAPICategoryUserDefaults": "CA92.1",
    }.items():
        if reason not in reasons.get(category, []):
            errors.append(f"Missing required API reason: {category}/{reason}.")
    entries = data.get("NSPrivacyCollectedDataTypes", [])
    names = [item.get("NSPrivacyCollectedDataType") for item in entries]
    if len(names) != len(set(names)):
        errors.append("Duplicate collected data categories.")
    if set(names) != COLLECTED_TYPES:
        errors.append("Collected data categories do not match the documented gateway data inventory.")
    for item in entries:
        if (item.get("NSPrivacyCollectedDataTypeLinked") is not True
                or item.get("NSPrivacyCollectedDataTypeTracking") is not False
                or item.get("NSPrivacyCollectedDataTypePurposes") != [PURPOSE]):
            errors.append(f"Invalid linkage, tracking or purpose: {item.get('NSPrivacyCollectedDataType')}.")
    return errors


def validate_info(data):
    errors = []
    ats = data.get("NSAppTransportSecurity", {})
    if ats.get("NSAllowsArbitraryLoads") or ats.get("NSAllowsArbitraryLoadsInWebContent"):
        errors.append("Global ATS bypass is not allowed in the release input.")
    if "audio" in data.get("UIBackgroundModes", []):
        errors.append("Background audio must not keep agent streaming alive.")
    for key in ("JonworkGatewayBaseURL", "JonworkGatewayEnvironment"):
        if not data.get(key):
            errors.append(f"Missing gateway deployment setting: {key}.")
    schemes = [scheme for item in data.get("CFBundleURLTypes", [])
               for scheme in item.get("CFBundleURLSchemes", [])]
    if "jonwork" not in schemes:
        errors.append("Missing Jonwork URL scheme.")
    return errors


def validate_usage_catalog(data):
    errors = []
    strings = data.get("strings", {})
    keys = {
        "NSCameraUsageDescription", "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription", "NSPhotoLibraryAddUsageDescription",
    }
    for key in keys:
        localizations = strings.get(key, {}).get("localizations", {})
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value", "").strip():
                errors.append(f"Missing permission description: {key}/{language}.")
    return errors


def release_blockers(record):
    blockers = []
    gates = record.get("gates", {})
    for name in sorted(RELEASE_GATES):
        gate = gates.get(name, {})
        if gate.get("status") != "verified" or not gate.get("evidence", "").strip():
            blockers.append(f"{name}: {gate.get('detail', 'Missing verified evidence.')}" )
    return blockers


def validate_icons(folder):
    errors = []
    catalog = json.loads((folder / "Contents.json").read_text())
    ios_images = [item for item in catalog.get("images", []) if item.get("platform") == "ios"]
    if not ios_images:
        errors.append("Missing iOS app icon.")
    for image in ios_images:
        filename = image.get("filename", "")
        try:
            data = (folder / filename).read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 33:
                raise ValueError("Not a PNG image")
            width, height = struct.unpack(">II", data[16:24])
            if (width, height) != (1024, 1024):
                errors.append(f"iOS icon must be 1024x1024: {filename}.")
            if data[25] in (4, 6):
                errors.append(f"iOS icon contains an alpha channel: {filename}.")
            cursor = 8
            while cursor + 12 <= len(data):
                size = struct.unpack(">I", data[cursor:cursor + 4])[0]
                if data[cursor + 4:cursor + 8] == b"tRNS":
                    errors.append(f"iOS icon contains transparency: {filename}.")
                cursor += size + 12
        except (OSError, ValueError, struct.error) as error:
            errors.append(f"Cannot inspect icon {filename}: {error}")
    return errors


def check_source(root):
    errors = []
    errors.extend(validate_icons(root / "Jonwork/Resources/Assets.xcassets/AppIcon.appiconset"))
    for path, validator, loader in (
        ("Jonwork/Resources/PrivacyInfo.xcprivacy", validate_manifest, plistlib.loads),
        ("Jonwork/Resources/InfoPlist/Info-iOS.plist", validate_info, plistlib.loads),
        ("Jonwork/Resources/InfoPlist.xcstrings", validate_usage_catalog, json.loads),
    ):
        try:
            errors.extend(validator(loader((root / path).read_bytes())))
        except (OSError, ValueError, plistlib.InvalidFileException, TypeError, AttributeError) as error:
            errors.append(f"Cannot validate {path}: {error}")
    project_path = root / "Jonwork.xcodeproj/project.pbxproj"
    project = project_path.read_text()
    if "FlowDown.xcodeproj" in project or re.search(r"\bname = FlowDown;", project):
        errors.append("Main Xcode project still uses the upstream product name.")
    if "com.jonwork.ios" not in project:
        errors.append("Missing product-owned bundle identifier.")
    release_config = (root / "Jonwork/Configuration/Release.xcconfig").read_text()
    if "agent.jonwork.com" not in release_config or "ENVIRONMENT = production;" not in release_config:
        errors.append("Release gateway must use the production deployment configuration.")
    for path in (
        "Jonwork.xcworkspace/contents.xcworkspacedata",
        "Jonwork.xcodeproj/xcshareddata/xcschemes/Jonwork.xcscheme",
        "JonworkTests.xctestplan",
    ):
        if not (root / path).is_file():
            errors.append(f"Missing renamed build input: {path}.")
    for path in ("JonworkTranslationProvider/AppGroup.swift", "JonworkWidgets/WidgetsAttributes.swift"):
        if not (root / path).is_file():
            errors.append(f"Missing shared extension source (check symlink target): {path}.")
    for language in LANGUAGES:
        path = root / f"Jonwork/BundledResources/{language}.lproj/PrivacyPolicy.md"
        if not path.is_file() or "github.com/xiz2680/jonwork-ios/issues" not in path.read_text():
            errors.append(f"Missing privacy policy/support contact: {language}.")
    licenses = (root / "LICENSE").read_text()
    provenance = root / "docs/UPSTREAM_PROVENANCE.md"
    if "GNU AFFERO GENERAL PUBLIC LICENSE" not in licenses or not provenance.is_file():
        errors.append("Missing AGPL license or upstream attribution record.")
    return errors


def check_bundle(app):
    errors = []
    try:
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != "com.jonwork.ios":
            errors.append("Built app does not use the production bundle identifier.")
        if info.get("CFBundleDisplayName") != "Jonwork":
            errors.append("Built app display name is not Jonwork.")
        if info.get("JonworkGatewayBaseURL") != "https://agent.jonwork.com":
            errors.append("Built app is not configured for the production gateway.")
        errors.extend(validate_info(info))
        errors.extend(validate_manifest(plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())))
        for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                    "NSSpeechRecognitionUsageDescription", "NSPhotoLibraryAddUsageDescription"):
            if not info.get(key):
                errors.append(f"Built app is missing {key}.")
        # Inspect every bundled SDK manifest instead of assuming the app covers SDKs.
        for manifest in app.rglob("PrivacyInfo.xcprivacy"):
            plistlib.loads(manifest.read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        errors.append(f"Cannot inspect built app: {error}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="Also fail on unverified release gates.")
    parser.add_argument("--app", type=Path, help="Inspect a built production .app (not a signing check).")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    errors = check_source(ROOT)
    if args.app:
        errors.extend(check_bundle(args.app))
    record = json.loads((ROOT / "docs/appstore-release.json").read_text())
    blockers = release_blockers(record)
    result = {"source_errors": errors, "release_blockers": blockers,
              "ready_for_submission": not errors and not blockers}
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Local input errors: {len(errors)}; unverified release gates: {len(blockers)}")
        for error in errors:
            print(f"FAIL: {error}")
        for blocker in blockers:
            print(f"BLOCKED: {blocker}")
        print("Local source checks do not establish App Store acceptance or signed distribution readiness.")
    return 1 if errors or (args.strict and blockers) else 0


if __name__ == "__main__":
    sys.exit(main())
