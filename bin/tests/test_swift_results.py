"""Keep passed assertions from concealing diagnostics or incomplete parameterized coverage."""

import importlib.machinery
import importlib.util
from pathlib import Path
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

    def test_missing_parameter_results_fail_even_if_method_says_passed(self):
        tree = {"nodeIdentifier": "SilenceSchedulerTests/foregroundTaskPriority(priority:)",
                "result": "Passed", "children": [
                    {"nodeType": "Arguments", "name": "TaskPriority.high", "result": "Passed"}]}
        self.assertTrue(any("TaskPriority.background" in error for error in results.check_arguments(tree)))


if __name__ == "__main__":
    unittest.main()
