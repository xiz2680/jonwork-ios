#!/usr/bin/env python3
"""Exercise the actual wrapper with synthetic logs and a local compiler stub."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


WRAPPER = Path(__file__).with_name("run_xcodebuild.sh")
PREFIX = "2026-10-14 13:26:59.333156+0800 Jonwork[73165:5429693] [ProcessSuspension] 0x11f178540 - ProcessAssertion::acquireSync Failed to acquire RBS assertion '"
WATCHDOG = PREFIX + "XPCConnectionTerminationWatchdog' for process with PID=73287, error: (null)"
SUSPENDED = PREFIX + "WebProcess NearSuspended Assertion' for process with PID=73287, error: (null)"
ALL_NULL = [WATCHDOG, SUSPENDED, WATCHDOG.replace("XPCConnectionTerminationWatchdog", "NetworkProcess Background Assertion"), WATCHDOG.replace("XPCConnectionTerminationWatchdog", "WebProcess Background Assertion")]


class XcodebuildLogClassifierTests(unittest.TestCase):
    def run_wrapper(self, lines, compiler_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "fixture.log"
            fixture.write_text("\n".join(lines) + "\n")
            compiler = root / "xcodebuild"
            compiler.write_text('#!/bin/sh\ncat "$CLASSIFIER_FIXTURE_LOG"\nexit "$CLASSIFIER_FIXTURE_EXIT"\n')
            compiler.chmod(0o755)
            beautifier = root / "xcbeautify"
            beautifier.write_text("#!/bin/sh\ncat\n")
            beautifier.chmod(0o755)
            environment = dict(os.environ)
            environment.update({
                "PATH": str(root) + os.pathsep + environment["PATH"],
                "XCBUILD_LABEL": "classifier-fixture",
                "XCBUILD_FORCE_PTY": "0",
                "CLASSIFIER_FIXTURE_LOG": str(fixture),
                "CLASSIFIER_FIXTURE_EXIT": str(compiler_exit),
            })
            return subprocess.run(["/bin/zsh", str(WRAPPER)], env=environment, capture_output=True, text=True, timeout=10)

    def test_exact_four_patterns_are_classified_and_raw_lines_retained(self):
        result = self.run_wrapper(ALL_NULL + ["** TEST SUCCEEDED **"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("classified 4 exact null WebKit process-assertion diagnostics", result.stdout)
        for line in ALL_NULL:
            self.assertIn(line, result.stdout)

    def test_additional_two_observed_background_patterns_are_exact_and_raw_retained(self):
        names = ["NetworkProcess Background Assertion", "WebProcess Background Assertion"]
        lines = [WATCHDOG.replace("XPCConnectionTerminationWatchdog", name) for name in names]
        result = self.run_wrapper(lines + ["** TEST SUCCEEDED **"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("classified 2 exact null WebKit process-assertion diagnostics", result.stdout)
        for line in lines:
            self.assertIn(line, result.stdout)
            negatives = [
                line.replace("(null)", "(actual failure)"),
                line.replace("[ProcessSuspension]", "[OtherProducer]"),
                line.replace("Jonwork[", "OtherApp["),
                line.replace("Background Assertion", "Other Assertion"),
                line + " error: additional failure",
                "error: " + line,
            ]
            for diagnostic in negatives:
                with self.subTest(diagnostic=diagnostic):
                    failed = self.run_wrapper([diagnostic, "** TEST SUCCEEDED **"])
                    self.assertEqual(failed.returncode, 1)
                    self.assertIn(diagnostic, failed.stdout + failed.stderr)

    def test_nonnull_changed_names_prefixes_and_lookalikes_remain_errors(self):
        cases = [
            WATCHDOG.replace("(null)", "(actual failure)"),
            WATCHDOG.replace("XPCConnectionTerminationWatchdog", "OtherAssertion"),
            WATCHDOG.replace("[ProcessSuspension]", "[OtherProducer]"),
            WATCHDOG.replace("Jonwork[", "OtherApp["),
            WATCHDOG.replace("acquireSync", "acquireAsync"),
            WATCHDOG.replace("+0800", ""),
            WATCHDOG + " error: additional failure",
            "error: " + WATCHDOG,
            "lookalike " + WATCHDOG,
        ]
        for diagnostic in cases:
            with self.subTest(diagnostic=diagnostic):
                result = self.run_wrapper([diagnostic, "** TEST SUCCEEDED **"])
                self.assertEqual(result.returncode, 1)
                self.assertIn(diagnostic, result.stdout + result.stderr)

    def test_compiler_linker_swift_and_test_failure_diagnostics_are_fatal(self):
        cases = [
            "/tmp/Source With Spaces.swift:12:4: error: missing value",
            "error: emit-module command failed",
            "clang: error: linker command failed",
            "ld: error: missing symbol",
            "Swift/Array.swift:12: Fatal error: invalid index",
            "Jonwork/Example.swift:57: Assertion failed",
            "Test crashed with signal trap.",
            "✘ Test fixture() recorded an issue at Example.swift:12: Expectation failed",
            "Testing failed:",
            "Failing tests:",
        ]
        for diagnostic in cases:
            with self.subTest(diagnostic=diagnostic):
                result = self.run_wrapper([WATCHDOG, diagnostic, "** TEST SUCCEEDED **"])
                self.assertEqual(result.returncode, 1)
                self.assertIn(diagnostic, result.stdout + result.stderr)

    def test_every_failed_action_marker_overrides_positive_marker(self):
        for action in ["BUILD", "TEST", "ARCHIVE", "CLEAN", "ANALYZE"]:
            with self.subTest(action=action):
                result = self.run_wrapper([WATCHDOG, "** " + action + " FAILED **", "** TEST SUCCEEDED **"])
                self.assertEqual(result.returncode, 1)

    def test_nonzero_exit_is_preserved_despite_success_marker_and_classified_lines(self):
        result = self.run_wrapper([WATCHDOG, SUSPENDED, "** TEST SUCCEEDED **"], compiler_exit=65)
        self.assertEqual(result.returncode, 65)
        self.assertIn("exit=65", result.stderr)

    def test_each_of_four_patterns_preserves_every_failure_gate(self):
        failures = [
            "/tmp/Source.swift:12:4: error: missing value",
            "error: Swift compilation failed",
            "ld: error: missing symbol",
            "Jonwork/Source.swift:57: Assertion failed",
            "Test crashed with signal trap.",
            "✘ Test fixture() recorded an issue at Source.swift:12: Expectation failed",
            "Testing failed:",
            "Failing tests:",
        ] + ["** " + action + " FAILED **" for action in ["BUILD", "TEST", "ARCHIVE", "CLEAN", "ANALYZE"]]
        for line in ALL_NULL:
            name = line.split("assertion '")[1].split("'")[0]
            variants = [
                line.replace("(null)", "(actual failure)"),
                line.replace(name, "OtherAssertion"),
                line.replace("Jonwork[", "OtherApp["),
                line.replace("[ProcessSuspension]", "[OtherProducer]"),
                line + " error: additional failure",
                "error: " + line,
            ]
            for diagnostic in variants:
                with self.subTest(assertion=name, variant=diagnostic):
                    result = self.run_wrapper([diagnostic, "** TEST SUCCEEDED **"])
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(diagnostic, result.stdout + result.stderr)
            for diagnostic in failures:
                with self.subTest(assertion=name, failure=diagnostic):
                    result = self.run_wrapper([line, diagnostic, "** TEST SUCCEEDED **"])
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(diagnostic, result.stdout + result.stderr)
            with self.subTest(assertion=name, nonzero_exit=True):
                result = self.run_wrapper([line, "** TEST SUCCEEDED **"], compiler_exit=65)
                self.assertEqual(result.returncode, 65)

    def test_clean_success_and_unclassified_runtime_errors(self):
        self.assertEqual(self.run_wrapper(["** BUILD SUCCEEDED **"]).returncode, 0)
        diagnostic = "2026-10-14 13:26:59.333156+0800 Jonwork[73165:5429693] error: runtime failure"
        result = self.run_wrapper([diagnostic, "** TEST SUCCEEDED **"])
        self.assertEqual(result.returncode, 1)
        self.assertIn(diagnostic, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
