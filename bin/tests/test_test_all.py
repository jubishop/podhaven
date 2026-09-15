"""Exercise the local test gate with isolated repositories and fake platform tools."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FAKE = r'''
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
base = pathlib.Path(os.environ['TEST_ALL_FIXTURE'])
with (base / 'events').open('a') as stream:
    stream.write(json.dumps([name, args]) + '\n')
if name == 'xcodebuild' and '-version' in args:
    print('Xcode ' + os.environ.get('TEST_XCODE_VERSION', '27.0'))
elif name == 'xcrun' and args == ['swift', '--version']:
    print('Apple Swift version ' + os.environ.get('TEST_SWIFT_VERSION', '6.4'))
elif name == 'sw_vers':
    print(os.environ.get('TEST_MACOS_VERSION', '27.0'))
elif name == 'with-test-accessibility':
    sys.exit(subprocess.run(args, check=False).returncode)
elif name == 'xcrun' and args[:2] == ['swift', 'test']:
    print('Executed 1 test, with 0 failures')
    if os.environ.get('TEST_MACRO_WARNING'): print('warning: unused result')
elif name == 'xcodebuild':
    assert not os.environ.get('SDKROOT'), 'Xcode must choose the SDK for its destination'
    assert '-hideShellScriptEnvironment' in args
    assert args[args.index('-destination') + 1] == 'platform=macOS,name=My Mac'
    assert 'LM_FORCE_LINK_GENERATION=YES' in args
    assert not any(arg.startswith(('-only-testing', '-skip-testing')) for arg in args)
    if not os.environ.get('TEST_MISSING_BUNDLE'):
        pathlib.Path(args[args.index('-resultBundlePath') + 1]).mkdir()
    print('Tests completed')
    if os.environ.get('TEST_CHANGE_CHECKOUT'):
        pathlib.Path('source.txt').write_text('changed during tests')
    if os.environ.get('TEST_STAGE_CHECKOUT'):
        subprocess.run(['git', 'add', '.'], check=True)
    if os.environ.get('TEST_BUILD_FAILURE'): sys.exit(65)
elif name == 'xcrun' and args[:2] == ['xcresulttool', 'get']:
    if not pathlib.Path(args[args.index('--path') + 1]).is_dir(): sys.exit(1)
    if 'summary' in args:
        print(json.dumps({'result': 'Passed', 'passedTests': 20,
                          'failedTests': 0, 'skippedTests': int(os.environ.get('TEST_SKIPPED', '0'))}))
    elif 'build-results' in args:
        print(json.dumps({'errorCount': 0, 'warningCount': 0, 'analyzerWarningCount': 0}))
    else:
        expected = {
            'WorkerTaskPriorityTests/backgroundExecution(process:)': [
                '.silenceAnalysis', '.transcription', '.embeddingComputation',
                '.publisherTranscripts', '.cachePurge', '.feedRefresh'],
            'BackgroundTaskSchedulerTests/executionPriority(priority:override:)': [
                f'TaskPriority.{priority}, .{override}' for priority in ('background', 'low')
                for override in ('unchanged', 'high', 'inherit')],
            'SilenceSchedulerTests/foregroundTaskPriority(priority:)': [
                'TaskPriority.background', 'TaskPriority.high']}
        print(json.dumps([{'nodeIdentifier': key, 'children': [
            {'nodeType': 'Arguments', 'name': name, 'result': 'Passed'} for name in names]}
            for key, names in expected.items()]))
elif name == 'xcrun' and args[:2] == ['xcresulttool', 'export']:
    output = pathlib.Path(args[args.index('--output-path') + 1])
    output.mkdir(parents=True)
    (output / 'StandardOutputAndStandardError.txt').write_text('Tests completed')
elif name in ('check', 'lint-swift-format', 'test_skill.py', 'test_helper.py'):
    print('Ran ' + os.environ.get('TEST_PYTHON_COUNT', '1') + ' test in 0.001s')
    print('OK (skipped=1)' if os.environ.get('TEST_PYTHON_SKIPPED') else 'OK')
    if os.environ.get('TEST_FAIL_STAGE') == name: sys.exit(23)
else:
    raise SystemExit('Unexpected command: ' + repr([name, args]))
'''


class TestAllTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven test all ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        for name in ("test-all", "check-swift-results"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        self.commands = self.base / "commands"
        self.commands.mkdir()
        for path in (self.commands / "xcodebuild", self.commands / "xcrun", self.commands / "sw_vers",
                     self.repo / "bin/check", self.repo / "bin/lint-swift-format",
                     self.repo / "bin/with-test-accessibility",
                     self.repo / ".agents/skills/example/test_skill.py",
                     self.repo / ".agents/scripts/example/test_helper.py"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        (self.repo / "bin/tests").mkdir()
        (self.repo / "bin/tests/probe.sh").write_text(
            '#!/bin/bash\nprintf shell > "$TEST_ALL_FIXTURE/shell-ran"\n')
        (self.repo / ".gitignore").write_text('.cache/\n')
        (self.repo / "source.txt").write_text("original")
        self.env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                    "TEST_ALL_FIXTURE": str(self.base)}
        for key in tuple(self.env):
            if key.startswith("GIT_") or key.startswith("TEST_") and key != "TEST_ALL_FIXTURE":
                self.env.pop(key)
        self.env.pop("SDKROOT", None)
        self.git("init", "--quiet")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                 "commit", "--quiet", "-m", "fixture")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo, env=self.env, text=True).strip()

    def run_all(self, *args, **env):
        return subprocess.run([sys.executable, "-B", str(self.repo / "bin/test-all"), *args],
                              cwd=self.base, env={**self.env, **env}, text=True,
                              capture_output=True, timeout=15)

    def report(self):
        return json.loads(next((self.repo / ".cache/test-all").glob("*/run.json")).read_text())

    def test_complete_run_includes_separate_suites_and_records_revision(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertIn(["check", ["--full"]], events)
        self.assertTrue(any(name == "with-test-accessibility" and args[0] == "xcodebuild"
                            for name, args in events))
        self.assertTrue(any(name == "test_skill.py" for name, _ in events))
        self.assertTrue(any(name == "test_helper.py" for name, _ in events))
        self.assertEqual((self.base / "shell-ran").read_text(), "shell")
        self.assertEqual(self.report()["checkout"]["revision"], self.git("rev-parse", "HEAD"))
        self.assertEqual(self.report()["checkout"]["status"], "")
        self.assertEqual(self.report()["result"], "passed")

    def test_failures_never_leave_a_passing_report(self):
        for setting in ("TEST_BUILD_FAILURE", "TEST_MISSING_BUNDLE", "TEST_SKIPPED",
                        "TEST_MACRO_WARNING", "TEST_CHANGE_CHECKOUT", "TEST_PYTHON_SKIPPED"):
            with self.subTest(setting=setting):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                (self.repo / "source.txt").write_text("original")
                result = self.run_all(**{setting: "1"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.report()["result"], "failed")

    def test_empty_python_suite_fails(self):
        result = self.run_all(TEST_PYTHON_COUNT="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.report()["result"], "failed")

    def test_staging_unchanged_contents_does_not_invalidate_tests(self):
        (self.repo / "new.txt").write_text("new source")
        result = self.run_all(TEST_STAGE_CHECKOUT="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.report()["result"], "passed")

    def test_inherited_host_sdk_does_not_override_the_app_sdk(self):
        result = self.run_all(SDKROOT="/wrong/MacOSX.sdk")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_skill_failure_stops_before_swift_build(self):
        result = self.run_all(TEST_FAIL_STAGE="test_skill.py")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.report()["result"], "failed")
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "xcodebuild" and "test" in args for name, args in events))

    def test_ensure_reuses_only_intact_clean_full_evidence(self):
        result = self.run_all("--ensure")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_all("--ensure", TEST_BUILD_FAILURE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list((self.repo / ".cache/test-all").glob("*/run.json"))), 1)
        log = next((self.repo / ".cache/test-all").glob("*/xcodebuild.log"))
        log.write_text(log.read_text() + "\nwarning: changed evidence\n")
        result = self.run_all("--verify")
        self.assertNotEqual(result.returncode, 0)
        result = self.run_all("--ensure", TEST_BUILD_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)

    def test_verify_rejects_missing_failed_stale_or_dirty_evidence(self):
        self.assertNotEqual(self.run_all("--verify").returncode, 0)
        self.assertEqual(self.run_all().returncode, 0)
        path = next((self.repo / ".cache/test-all").glob("*/run.json"))
        original = path.read_text()
        for field, value in (("result", "failed"), ("checkout", {}), ("checkout_after", {}),
                             ("xcode", "Xcode 26"), ("destination", "simulator")):
            with self.subTest(field=field):
                report = json.loads(original)
                report[field] = value
                path.write_text(json.dumps(report))
                self.assertNotEqual(self.run_all("--verify").returncode, 0)
        path.write_text(original)
        self.assertEqual(self.run_all("--verify").returncode, 0)
        (self.repo / "source.txt").write_text("dirty")
        self.assertNotEqual(self.run_all("--ensure").returncode, 0)
        self.assertEqual(len(list((self.repo / ".cache/test-all").glob("*/run.json"))), 1)
        (self.repo / "source.txt").write_text("original")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                 "commit", "--allow-empty", "-m", "new revision")
        self.assertNotEqual(self.run_all("--verify").returncode, 0)

    def test_expected_revision_and_changed_toolchain_reject_reuse(self):
        self.assertEqual(self.run_all().returncode, 0)
        self.assertNotEqual(self.run_all("--verify", "--revision", "wrong").returncode, 0)
        self.assertNotEqual(self.run_all("--verify", TEST_SWIFT_VERSION="6.5").returncode, 0)
        self.assertNotEqual(self.run_all("--verify", TEST_XCODE_VERSION="26.5").returncode, 0)

    def test_latest_failure_does_not_reuse_an_older_success(self):
        self.assertEqual(self.run_all().returncode, 0)
        self.assertNotEqual(self.run_all(TEST_SKIPPED="1").returncode, 0)
        self.assertNotEqual(self.run_all("--verify").returncode, 0)
        latest = max((self.repo / ".cache/test-all").glob("*/run.json"),
                     key=lambda path: path.stat().st_mtime_ns)
        latest.unlink()
        self.assertNotEqual(self.run_all("--verify").returncode, 0)

    def test_content_digest_catches_changes_hidden_from_git_status(self):
        self.assertEqual(self.run_all().returncode, 0)
        self.git("update-index", "--assume-unchanged", "source.txt")
        (self.repo / "source.txt").write_text("hidden change")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertNotEqual(self.run_all("--verify").returncode, 0)

    def test_preflight_does_not_run_tests_or_write_evidence(self):
        result = self.run_all("--preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repo / ".cache").exists())

    def test_unsupported_xcode_stops_before_tests(self):
        result = self.run_all(TEST_XCODE_VERSION="26.5")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode 27+", result.stderr)
        self.assertFalse((self.repo / ".cache").exists())

    def test_unsupported_macos_stops_before_tests(self):
        result = self.run_all(TEST_MACOS_VERSION="26.6.2")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("My Mac tests require macOS 27+", result.stderr)
        self.assertFalse((self.repo / ".cache").exists())


if __name__ == "__main__":
    unittest.main()
