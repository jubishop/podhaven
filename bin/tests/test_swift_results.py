"""Keep passed assertions from concealing diagnostics or incomplete parameterized coverage."""

import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("swift_results", str(ROOT / "bin/check-swift-results"))
spec = importlib.util.spec_from_loader(loader.name, loader)
results = importlib.util.module_from_spec(spec)
loader.exec_module(results)


class SwiftResultTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"result": "Passed", "passedTests": 10, "failedTests": 0}
        self.build = {"errorCount": 0, "warningCount": 0, "analyzerWarningCount": 0}

    def test_missing_bundle_has_an_actionable_error_without_a_traceback(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "missing.xcresult"
            log = Path(folder) / "xcodebuild.log"
            log.write_text("error: Grant Accessibility access")
            result = subprocess.run(
                [sys.executable, str(ROOT / "bin/check-swift-results"), str(bundle), "--build-log", str(log)],
                capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing Swift test result bundle", result.stderr)
            self.assertIn(str(log), result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse(bundle.with_suffix(".validation").exists())

    def test_passed_assertions_do_not_hide_runtime_warnings(self):
        for warning in ("Unbalanced calls to begin/end appearance transitions for <UIHostingController>",
                        "Main Thread Checker: UI API called on a background thread",
                        "Accessing State's value outside of being installed on a View.",
                        "Modifying state during view update, this will cause undefined behavior."):
            with self.subTest(warning=warning):
                self.assertTrue(results.failures(self.summary, self.build, {"stdout": warning}, "Build succeeded"))

    def test_missing_evidence_and_zero_tests_fail(self):
        self.assertTrue(results.failures(self.summary, self.build, {}, "Build succeeded"))
        self.summary["passedTests"] = 0
        self.assertTrue(results.failures(self.summary, self.build, {"stdout": "Finished"}, "Build succeeded"))

    def test_skipped_tests_do_not_establish_a_complete_pass(self):
        self.summary["skippedTests"] = 28
        self.assertTrue(results.failures(self.summary, self.build,
                                        {"stdout": "Finished"}, "Build succeeded"))

    def test_failed_results_and_build_diagnostics_fail(self):
        for field in self.build:
            with self.subTest(field=field):
                build = {**self.build, field: 1}
                self.assertTrue(results.failures(self.summary, build, {"stdout": "Finished"}, "Build succeeded"))
        self.summary["result"] = "Failed"
        self.assertTrue(results.failures(self.summary, self.build, {"stdout": "Finished"}, "Build succeeded"))

    def test_expected_application_error_logging_is_not_a_runtime_diagnostic(self):
        self.assertEqual(results.failures(self.summary, self.build,
                         {"stdout": "warning PodHaven: simulated decode failure\nTest passed"}, "Build succeeded"), [])

    def test_raw_warning_fails_even_when_result_bundle_reports_zero(self):
        for log in ("", "appintentsmetadataprocessor warning: Metadata extraction skipped.",
                    "warning: unused result"):
            with self.subTest(log=log):
                self.assertTrue(results.failures(self.summary, self.build, {"stdout": "Finished"}, log))

    def test_only_approved_sentry_setter_warning_is_accepted(self):
        source = ROOT / "PodHaven/AppLauncher.swift"
        line = next(i for i, text in enumerate(source.read_text().splitlines(), 1)
                    if "options.beforeSendWithHint =" in text)
        message = ("Setter for 'beforeSendWithHint' is deprecated: In the next major version, "
                   "the hint parameter will be added to `beforeSend` directly and this callback "
                   "will be removed. Use this only to adopt hints ahead of the next major version.")
        warning = {"issueType": "DeprecatedDeclaration", "message": message,
                   "sourceURL": source.as_uri() + f"#StartingLineNumber={line - 1}"}
        build = {**self.build, "warningCount": 1, "warnings": [warning]}
        log = f"{source}:{line}:5: warning: {message[0].lower() + message[1:]} [#DeprecatedDeclaration]"
        self.assertEqual(results.failures(self.summary, build, {"stdout": "Finished"}, log), [])
        for changed in ({**warning, "message": "Other API is deprecated"},
                        {**warning, "sourceURL": warning["sourceURL"].replace("AppLauncher", "Other")},
                        {**warning, "issueType": "OtherWarning"},
                        {**warning, "sourceURL": source.as_uri() + "#StartingLineNumber=0"}):
            with self.subTest(changed=changed):
                self.assertTrue(results.failures(self.summary, {**build, "warnings": [changed]},
                                                {"stdout": "Finished"}, log))
        self.assertTrue(results.failures(self.summary, {**build, "warningCount": 2}, {"stdout": "Finished"}, log))
        self.assertTrue(results.failures(self.summary, build, {"stdout": "Finished"}, log + "\nwarning: unused result"))
        self.assertTrue(results.failures(self.summary, build, {"stdout": "Finished"}, log.replace("AppLauncher", "Other")))

    def test_missing_parameter_results_fail_even_if_method_says_passed(self):
        tree = {"nodeIdentifier": "SilenceSchedulerTests/foregroundTaskPriority(priority:)",
                "result": "Passed", "children": [
                    {"nodeType": "Arguments", "name": "TaskPriority.high", "result": "Passed"}]}
        self.assertTrue(any("TaskPriority.background" in error for error in results.check_arguments(tree)))


if __name__ == "__main__":
    unittest.main()
