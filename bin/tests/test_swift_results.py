"""Keep passed assertions from concealing diagnostics or incomplete parameterized coverage."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import hang_guard
import service_guard

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("swift_results", str(ROOT / "bin/check-swift-results"))
spec = importlib.util.spec_from_loader(loader.name, loader)
results = importlib.util.module_from_spec(spec)
loader.exec_module(results)

PRIORITY_INVERSION = ("Thread Performance Checker: Thread running at User-initiated quality-of-service class "
                      "waiting on a lower QoS thread running at Background quality-of-service class. "
                      "Investigate ways to avoid priority inversions")

# Serves the fixtures beside it as xcresulttool's JSON reports and exported test output.
FAKE_XCRUN = """
import pathlib, sys
args = sys.argv[1:]
fixtures = pathlib.Path(sys.argv[0]).parent
if args[:2] == ["xcresulttool", "export"]:
    output = pathlib.Path(args[args.index("--output-path") + 1]) / "PodHavenTests"
    output.mkdir(parents=True)
    (output / "StandardOutputAndStandardError.txt").write_text((fixtures / "stdout.txt").read_text())
else:
    name = "summary" if "summary" in args else "build" if "build-results" in args else "tests"
    print((fixtures / f"{name}.json").read_text())
"""


class SwiftResultTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"result": "Passed", "passedTests": 10, "failedTests": 0}
        self.build = {"errorCount": 0, "warningCount": 0, "analyzerWarningCount": 0}

    def test_missing_bundle_has_an_actionable_error_without_a_traceback(self):
        with tempfile.TemporaryDirectory() as folder:
            bundle = Path(folder) / "missing.xcresult"
            log = Path(folder) / "xcodebuild.log"
            log.write_text("error: Unable to launch PodHaven")
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
                        PRIORITY_INVERSION,
                        "Accessing State's value outside of being installed on a View.",
                        "Modifying state during view update, this will cause undefined behavior."):
            with self.subTest(warning=warning):
                self.assertTrue(results.failures(self.summary, self.build, {"stdout": warning}, "Build succeeded"))

    def check_bundle(self, nodes):
        with tempfile.TemporaryDirectory() as folder:
            fakes = Path(folder) / "bin"
            fakes.mkdir()
            xcrun = fakes / "xcrun"
            xcrun.write_text(f"#!{sys.executable}{FAKE_XCRUN}")
            xcrun.chmod(0o755)
            tests = {"testPlanConfigurations": [], "devices": [], "testNodes": nodes}
            for name, report in (("summary", self.summary), ("build", self.build), ("tests", tests)):
                (fakes / f"{name}.json").write_text(json.dumps(report))
            (fakes / "stdout.txt").write_text("Test run with 10 tests passed")
            bundle = Path(folder) / "TestResults.xcresult"
            bundle.mkdir()
            log = Path(folder) / "xcodebuild.log"
            log.write_text("** TEST SUCCEEDED **")
            return hang_guard.run(
                [sys.executable, str(ROOT / "bin/check-swift-results"), str(bundle), "--build-log", str(log)],
                capture_output=True, text=True,
                env={**os.environ, "PATH": str(fakes) + os.pathsep + os.environ["PATH"]})

    def test_runtime_warnings_in_the_result_bundle_fail(self):
        def tree(*warnings):
            return [{"nodeType": "Test Plan", "name": "PodHaven", "children": [
                {"nodeType": "Unit test bundle", "name": "PodHavenTests", "children": [
                    {"nodeType": "Test Suite", "name": "AppLauncherTests", "children": [
                        {"nodeType": "Test Case", "name": "outgoingFeedbackAttachments()",
                         "nodeIdentifier": "AppLauncherTests/outgoingFeedbackAttachments()",
                         "result": "Passed", "children": [
                             {"nodeType": "Repetition", "name": "Repetition 4", "nodeIdentifier": "4",
                              "result": "Passed",
                              "children": [{"nodeType": "Runtime Warning", "name": warning}
                                           for warning in warnings]}]}]}]}]}]

        clean = self.check_bundle(tree())
        self.assertEqual(clean.returncode, 0, clean.stderr)
        self.assertIn("Swift validation passed", clean.stdout)
        for warning in (PRIORITY_INVERSION, "An unrecognized runtime issue"):
            with self.subTest(warning=warning):
                result = self.check_bundle(tree(warning))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"AppLauncherTests/outgoingFeedbackAttachments(): {warning}", result.stderr)

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

    def test_only_approved_app_hang_tracking_warnings_are_accepted(self):
        source = ROOT / "PodHaven/Logging/AppHangReportingGate.swift"
        lines = source.read_text().splitlines()
        reason = ("is deprecated: App Hang tracking is deprecated and will be removed in v10 because it "
                  "can produce less relevant stack traces and false positives. Enable the MetricKit "
                  "integration for system-provided hang diagnostics.")
        warnings, logs = [], []
        for call in ("pauseAppHangTracking()", "resumeAppHangTracking()"):
            line = next(i for i, text in enumerate(lines, 1) if f"SentrySDK.{call}" in text)
            message = f"'{call}' {reason}"
            warnings.append({"issueType": "DeprecatedDeclaration", "message": message,
                             "sourceURL": source.as_uri() + f"#StartingLineNumber={line - 1}"})
            logs.append(f"{source}:{line}:28: warning: {message} [#DeprecatedDeclaration]")
        build = {**self.build, "warningCount": 2, "warnings": warnings}
        log = "\n".join(logs)
        self.assertEqual(results.failures(self.summary, build, {"stdout": "Finished"}, log), [])
        pause, resume = warnings
        for changed in ({**pause, "message": resume["message"]},
                        {**pause, "message": "'pauseAppHangTracking()' is deprecated"},
                        {**pause, "sourceURL": pause["sourceURL"].replace("AppHangReportingGate", "Other")},
                        {**pause, "sourceURL": resume["sourceURL"]},
                        {**pause, "issueType": "OtherWarning"}):
            with self.subTest(changed=changed):
                self.assertTrue(results.failures(self.summary, {**build, "warnings": [changed, resume]},
                                                {"stdout": "Finished"}, log))
        self.assertTrue(results.failures(self.summary, {**build, "warningCount": 3}, {"stdout": "Finished"}, log))
        self.assertTrue(results.failures(self.summary, build, {"stdout": "Finished"},
                                         log.replace("pauseAppHangTracking", "resumeAppHangTracking", 1)))
        self.assertTrue(results.failures(self.summary, build, {"stdout": "Finished"},
                                         log.replace("AppHangReportingGate", "Other")))

    def test_missing_parameter_results_fail_even_if_method_says_passed(self):
        tree = {"nodeIdentifier": "SilenceSchedulerTests/foregroundTaskPriority(priority:)",
                "result": "Passed", "children": [
                    {"nodeType": "Arguments", "name": "TaskPriority.high", "result": "Passed"}]}
        self.assertTrue(any("TaskPriority.background" in error for error in results.check_arguments(tree)))


if __name__ == "__main__":
    unittest.main()
