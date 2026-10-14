#!/usr/bin/env python3
"""Ordinary CLI validation fixtures; not compiler or product acceptance evidence."""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ExtractedLocalizationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = self.folder / "physical"
        self.alias = self.folder / "alias"
        self.root.mkdir()
        self.alias.symlink_to(self.root, target_is_directory=True)
        self.source = self.root / "Jonwork/Fixture.swift"
        self.source.parent.mkdir()
        self.source.write_text('import Foundation\nlet title = String(localized: "Fixture")\n')
        self.script = self.root / "Resources/DevKit/scripts/check_extracted_i18n.py"
        self.script.parent.mkdir(parents=True)
        shutil.copy2(Path(__file__).with_name("check_extracted_i18n.py"), self.script)
        self.manifest = self.folder / "manifest.json"
        self.manifest.write_text(json.dumps({"files": [{"path": "Jonwork/Fixture.swift", "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest()}]}))
        self.catalog = self.folder / "catalog.json"
        self.catalog.write_text(json.dumps({"strings": {"Fixture": {"localizations": {locale: {"stringUnit": {"value": locale + " fixture", "state": "translated"}} for locale in ["en", "de", "es", "fr", "ja", "ko", "zh-Hans"]}}}}))
        self.derived = self.folder / "derived"
        self.extraction = self.derived / "Build/Intermediates.noindex/Jonwork.build/Debug-iphonesimulator/Jonwork.build/Objects-normal/arm64/Fixture.stringsdata"
        self.extraction.parent.mkdir(parents=True)
        self.write_extraction(str(self.alias / "Jonwork/Fixture.swift"))

    def write_extraction(self, source, keys=True):
        self.extraction.write_text(json.dumps({"source": source, "tables": {"Localizable": [{"key": "Fixture"}] if keys else []}}))

    def check(self):
        return subprocess.run([sys.executable, str(self.script), "--derived-data", str(self.derived), "--catalog", str(self.catalog), "--manifest", str(self.manifest)], capture_output=True, text=True)

    def test_alias_of_actual_source_passes(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 extracted keys in 1 changed app sources across seven locales", result.stdout)

    def test_same_basename_and_bytes_outside_expected_root_fail(self):
        outside = self.folder / "outside/Fixture.swift"
        outside.parent.mkdir()
        shutil.copy2(self.source, outside)
        self.write_extraction(str(outside))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing extraction", result.stdout)

    def test_missing_nonstring_and_empty_sources_fail(self):
        for source in [None, 42, ""]:
            with self.subTest(source=source):
                self.write_extraction(source)
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("missing extraction", result.stdout)
        self.extraction.write_text(json.dumps({"tables": {"Localizable": [{"key": "Fixture"}]}}))
        self.assertNotEqual(self.check().returncode, 0)

    def test_changed_source_cannot_use_prior_manifest_and_extraction(self):
        self.source.write_text('import Foundation\nlet title = String(localized: "Changed")\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source differs from manifest", result.stderr)

    def test_empty_extraction_fails(self):
        self.write_extraction(str(self.source), keys=False)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no compiler-extracted keys", result.stdout)

    def test_missing_locale_fails(self):
        catalog = json.loads(self.catalog.read_text())
        del catalog["strings"]["Fixture"]["localizations"]["ko"]
        self.catalog.write_text(json.dumps(catalog))
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing translation: ko / Fixture", result.stdout)


if __name__ == "__main__":
    unittest.main()
