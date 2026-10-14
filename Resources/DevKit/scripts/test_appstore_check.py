import copy
import importlib.util
import json
import plistlib
import struct
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("appstore_check", Path(__file__).with_name("appstore_check.py"))
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class AppStoreCheckTests(unittest.TestCase):
    def setUp(self):
        self.manifest = plistlib.loads((CHECK.ROOT / "Jonwork/Resources/PrivacyInfo.xcprivacy").read_bytes())

    def test_current_manifest_is_valid(self):
        self.assertEqual(CHECK.validate_manifest(self.manifest), [])

    def test_empty_data_inventory_is_rejected(self):
        self.manifest["NSPrivacyCollectedDataTypes"] = []
        self.assertTrue(CHECK.validate_manifest(self.manifest))

    def test_duplicate_data_types_and_missing_purposes_are_rejected(self):
        self.manifest["NSPrivacyCollectedDataTypes"].append(copy.deepcopy(self.manifest["NSPrivacyCollectedDataTypes"][0]))
        self.manifest["NSPrivacyCollectedDataTypes"][0]["NSPrivacyCollectedDataTypePurposes"] = []
        errors = CHECK.validate_manifest(self.manifest)
        self.assertTrue(any("Duplicate" in error for error in errors))
        self.assertTrue(any("purpose" in error for error in errors))

    def test_background_audio_and_global_ats_bypass_are_rejected(self):
        info = plistlib.loads((CHECK.ROOT / "Jonwork/Resources/InfoPlist/Info-iOS.plist").read_bytes())
        self.assertEqual(CHECK.validate_info(info), [])
        info["UIBackgroundModes"] = ["audio"]
        info["NSAppTransportSecurity"]["NSAllowsArbitraryLoads"] = True
        self.assertEqual(len(CHECK.validate_info(info)), 2)

    def test_release_gate_needs_evidence_even_when_marked_verified(self):
        record = {"gates": {name: {"status": "verified", "evidence": ""} for name in CHECK.RELEASE_GATES}}
        self.assertEqual(len(CHECK.release_blockers(record)), len(CHECK.RELEASE_GATES))

    def test_missing_permission_translations_are_rejected(self):
        self.assertTrue(CHECK.validate_usage_catalog({"strings": {}}))

    def test_icons_reject_alpha_and_wrong_dimensions(self):
        source = CHECK.ROOT / "Jonwork/Resources/Assets.xcassets/AppIcon.appiconset/Jonwork-Light.png"
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "Contents.json").write_text(json.dumps({"images": [{"platform": "ios", "filename": "icon.png"}]}))
            data = bytearray(source.read_bytes())
            data[16:24] = struct.pack(">II", 512, 512)
            data[25] = 6
            (folder / "icon.png").write_bytes(data)
            errors = CHECK.validate_icons(folder)
            self.assertTrue(any("1024x1024" in error for error in errors))
            self.assertTrue(any("alpha" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
