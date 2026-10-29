"""Exercise the local test gate with isolated repositories and fake platform tools."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
FAKE = r'''
import fcntl, json, os, pathlib, signal, subprocess, sys, time
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
elif name == 'xcrun' and args[:2] == ['swift', 'test']:
    print('Executed 1 test, with 0 failures')
    if os.environ.get('TEST_MACRO_WARNING'): print('warning: unused result')
elif name == 'xcodebuild':
    lock_path = pathlib.Path.home() / '.cache/podhaven/my-mac-tests.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            sys.exit('xcodebuild test ran without the My Mac test lock')
        except BlockingIOError:
            pass
    assert not os.environ.get('SDKROOT'), 'Xcode must choose the SDK for its destination'
    assert '-hideShellScriptEnvironment' in args
    assert args[args.index('-destination') + 1] == 'platform=macOS,name=My Mac'
    assert 'LM_FORCE_LINK_GENERATION=YES' in args
    bundle = pathlib.Path(args[args.index('-resultBundlePath') + 1])
    performance = bundle.stem == 'SiriPerformance'
    fault = os.environ.get('TEST_PERFORMANCE_FAULT') if performance else None
    selection = '-only-testing' if performance else '-skip-testing'
    assert [arg for arg in args if arg.startswith(('-only-testing', '-skip-testing'))] == [
        selection + ':PodHavenTests/SiriLargeCatalogTests']
    if os.environ.get('TEST_HOLD_FIFO') and not performance:
        pathlib.Path(os.environ['TEST_HOLD_FIFO']).read_text()
    stalled = os.environ.get('TEST_HOST_STALL') == bundle.stem
    if stalled:
        ended = subprocess.Popen([sys.executable, '-c', ''])
        ended.wait()
        print(f"Test suite 'Selected tests' started on 'My Mac - PodHaven ({ended.pid})'")
        print('Restarting after unexpected exit, crash, or test timeout')
        host = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        (base / 'stalled-host').write_text(str(host.pid))
        print(f"Test suite 'Selected tests' started on 'My Mac - PodHaven ({host.pid})'", flush=True)
        try:
            host.wait(timeout=10)
        except subprocess.TimeoutExpired:
            host.kill()
            host.wait()
        print(f"Test case 'StalledTests/waits()' failed on 'My Mac - PodHaven ({host.pid})' (600.000 seconds)")
    if os.environ.get('TEST_HOST_BUSY') and not performance:
        quiet = float(os.environ['TEST_HOST_BUSY'])
        time.sleep(quiet * 1.5)
        host = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        for index in range(40):
            print(f"Test case 'BusyTests/step{index}()' passed on 'My Mac - PodHaven ({host.pid})'", flush=True)
            time.sleep(quiet / 20)
        host.kill()
        host.wait()
        time.sleep(quiet * 1.5)
    if not os.environ.get('TEST_MISSING_BUNDLE') and fault != 'missing-bundle':
        bundle.mkdir()
    print('Tests completed')
    if os.environ.get('TEST_CHANGE_CHECKOUT'):
        pathlib.Path('source.txt').write_text('changed during tests')
    if os.environ.get('TEST_STAGE_CHECKOUT'):
        subprocess.run(['git', 'add', '.'], check=True)
    if os.environ.get('TEST_ASSUME_CHECKOUT'):
        subprocess.run(['git', 'update-index', '--assume-unchanged', 'source.txt'], check=True)
    if os.environ.get('TEST_BUILD_FAILURE') or fault == 'build' or stalled: sys.exit(65)
elif name == 'xcrun' and args[:2] == ['xcresulttool', 'get']:
    bundle = pathlib.Path(args[args.index('--path') + 1])
    if not bundle.is_dir(): sys.exit(1)
    fault = os.environ.get('TEST_PERFORMANCE_FAULT') if bundle.stem == 'SiriPerformance' else None
    if 'summary' in args:
        print(json.dumps({'result': 'Failed' if fault == 'failed-result' else 'Passed',
                          'passedTests': 0 if fault == 'empty' else 20,
                          'failedTests': int(fault == 'failed-result'),
                          'skippedTests': int(os.environ.get('TEST_SKIPPED', '0')) + int(fault == 'skipped')}))
    elif 'build-results' in args:
        print(json.dumps({'errorCount': 0, 'warningCount': int(fault == 'warning'), 'analyzerWarningCount': 0}))
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
    performance = pathlib.Path(args[args.index('--path') + 1]).stem == 'SiriPerformance'
    fault = os.environ.get('TEST_PERFORMANCE_FAULT') if performance else None
    (output / 'StandardOutputAndStandardError.txt').write_text(
        'Main Thread Checker: invalid access' if fault == 'runtime' else 'Tests completed')
elif name == 'sample':
    path = pathlib.Path(args[args.index('-file') + 1])
    path.write_text('Analysis of sampling PodHaven (pid ' + args[0] + ')\n')
    if path.name.endswith('-2.sample.txt'):
        os.kill(int(args[0]), signal.SIGTERM)
elif name == 'check' and '--no-reuse' not in args and (base / 'check-passed').exists():
    print('Reused the application checks that passed earlier; bin/check --full --no-reuse runs them again.')
elif name in ('check', 'lint-swift-format', 'test_skill.py', 'test_helper.py'):
    print('Ran ' + os.environ.get('TEST_PYTHON_COUNT', '1') + ' test in 0.001s')
    print('OK (skipped=1)' if os.environ.get('TEST_PYTHON_SKIPPED') else 'OK')
    if os.environ.get('TEST_FAIL_STAGE') == name: sys.exit(23)
    if name == 'check': (base / 'check-passed').touch()
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
        for name in ("test-all", "check-swift-results", "_my_mac_lock.py"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        self.commands = self.base / "commands"
        self.commands.mkdir()
        for path in (self.commands / "xcodebuild", self.commands / "xcrun", self.commands / "sw_vers",
                     self.commands / "sample",
                     self.repo / "bin/check", self.repo / "bin/lint-swift-format",
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
        (self.base / "home").mkdir()
        self.env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                    "TEST_ALL_FIXTURE": str(self.base), "HOME": str(self.base / "home")}
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

    def shorten_host_watch(self, quiet):
        script = self.repo / "bin/test-all"
        text = script.read_text()
        for name, value in (("QUIET_LOG_SECONDS", quiet), ("SAMPLE_GAP_SECONDS", quiet / 5),
                            ("POLL_SECONDS", quiet / 20)):
            text, count = re.subn(rf"^{name} = .+$", f"{name} = {value}", text, flags=re.M)
            self.assertEqual(count, 1, name)
        script.write_text(text)

    def test_complete_run_includes_separate_suites_and_records_revision(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertIn(["check", ["--full", "--no-reuse"]], events)
        self.assertTrue(any(name == "xcodebuild" and args[:1] == ["test"] for name, args in events))
        self.assertTrue(any(name == "test_skill.py" for name, _ in events))
        self.assertTrue(any(name == "test_helper.py" for name, _ in events))
        self.assertFalse((self.base / "shell-ran").exists())
        self.assertEqual(self.report()["checkout"]["revision"], self.git("rev-parse", "HEAD"))
        self.assertEqual(self.report()["checkout"]["status"], "")
        self.assertEqual(self.report()["result"], "passed")

    def test_siri_performance_runs_separately_and_both_runs_are_validated(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        builds = [args for name, args in events if name == "xcodebuild" and "test" in args]
        self.assertEqual(len(builds), 2)
        self.assertEqual([arg for arg in builds[0] if arg.startswith(("-only-testing", "-skip-testing"))],
                         ["-skip-testing:PodHavenTests/SiriLargeCatalogTests"])
        self.assertEqual([arg for arg in builds[1] if arg.startswith(("-only-testing", "-skip-testing"))],
                         ["-only-testing:PodHavenTests/SiriLargeCatalogTests"])
        bundles = [args[args.index("-resultBundlePath") + 1] for args in builds]
        self.assertEqual(len(set(bundles)), 2)
        for bundle in bundles:
            for command in (["get", "test-results", "summary"], ["get", "build-results"],
                            ["get", "test-results", "tests"], ["export", "diagnostics"]):
                self.assertTrue(any(name == "xcrun" and args[:1 + len(command)] == ["xcresulttool", *command]
                                    and args[args.index("--path") + 1] == bundle
                                    for name, args in events))
        artifacts = self.report()["artifacts"]
        self.assertIn("siri-performance.log", artifacts)
        self.assertIn("siri-performance-validation.log", artifacts)

    def test_siri_performance_failures_never_leave_a_passing_report(self):
        for fault in ("build", "missing-bundle", "failed-result", "empty", "skipped", "warning", "runtime"):
            with self.subTest(fault=fault):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all(TEST_PERFORMANCE_FAULT=fault)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.report()["result"], "failed")

    def test_concurrent_runs_from_different_checkouts_take_turns_on_my_mac(self):
        other = self.base / "other"
        shutil.copytree(self.repo, other, symlinks=True)
        gate = self.base / "gate"
        os.mkfifo(gate)
        reader = os.open(gate, os.O_RDONLY | os.O_NONBLOCK)
        writer = os.open(gate, os.O_WRONLY)
        os.close(reader)
        released = False
        processes = []

        def start(repo, **env):
            process = subprocess.Popen([sys.executable, "-B", str(repo / "bin/test-all")], cwd=self.base,
                                       env={**self.env, **env}, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            processes.append(process)
            return process

        def stop():
            if not released:
                os.close(writer)
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate()

        self.addCleanup(stop)
        watchdog = threading.Timer(60, lambda: [process.kill() for process in processes])
        watchdog.start()
        self.addCleanup(watchdog.cancel)
        first = start(self.repo, TEST_HOLD_FIFO=str(gate))
        for line in first.stdout:
            if line.startswith("Running xcodebuild;"):
                break
        else:
            self.fail("The first run never started its My Mac tests:\n" + first.stderr.read())
        second = start(other)
        waiting = second.stderr.readline()
        self.assertIn("Waiting for the My Mac test lock", waiting)
        self.assertIn(f"bin/test-all in {self.repo.resolve()}", waiting)
        os.close(writer)
        released = True
        first_output, first_errors = first.communicate(timeout=30)
        self.assertEqual(first.returncode, 0, first_output + first_errors)
        second_output, second_errors = second.communicate(timeout=30)
        self.assertEqual(second.returncode, 0, second_output + second_errors)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        owners = [Path(args[args.index("-resultBundlePath") + 1]).parents[3]
                  for name, args in events if name == "xcodebuild" and "test" in args]
        self.assertEqual(owners, [self.repo.resolve()] * 2 + [other.resolve()] * 2)

    def test_stalled_test_host_is_sampled_twice_without_ending_the_run(self):
        self.shorten_host_watch(1)
        for bundle, log in (("TestResults", "xcodebuild"), ("SiriPerformance", "siri-performance")):
            with self.subTest(phase=log):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                (self.base / "events").unlink(missing_ok=True)
                result = self.run_all(TEST_HOST_STALL=bundle)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                host = (self.base / "stalled-host").read_text()
                output = next((self.repo / ".cache/test-all").iterdir()).resolve()
                samples = [output / f"{log}-host-{host}-{index}.sample.txt" for index in (1, 2)]
                self.assertEqual(sorted(output.glob("*.sample.txt")), samples, result.stderr)
                events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
                self.assertEqual([(args[0], args[args.index("-file") + 1]) for name, args in events
                                  if name == "sample"], [(host, str(path)) for path in samples])
                self.assertIn("(600.000 seconds)", (output / f"{log}.log").read_text())
                self.assertTrue(any(name == "xcrun" and "xcresulttool" in args
                                    and args[args.index("--path") + 1] == str(output / f"{bundle}.xcresult")
                                    for name, args in events))
                report = self.report()
                self.assertEqual(report["result"], "failed")
                for path in samples:
                    self.assertIn(str(path), report["error"])
                    self.assertIn(str(path), result.stderr.split("error: ")[-1])

    def test_busy_host_and_quiet_logs_without_a_live_host_are_not_sampled(self):
        self.shorten_host_watch(1)
        result = self.run_all(TEST_HOST_BUSY="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "sample" for name, _ in events))
        self.assertEqual(list((self.repo / ".cache").rglob("*.sample.txt")), [])
        self.assertEqual(self.report()["result"], "passed")

    def test_run_under_the_lock_command_reuses_its_lock(self):
        result = subprocess.run([sys.executable, "-B", str(ROOT / "bin/with-my-mac-lock"),
                                 sys.executable, "-B", str(self.repo / "bin/test-all")],
                                cwd=self.base, env=self.env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Waiting", result.stderr)

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

    def test_missing_bundle_reports_launch_failure_without_result_inspection(self):
        result = self.run_all(TEST_MISSING_BUNDLE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.report()["result"], "failed")
        self.assertIn("did not produce a result bundle", result.stderr)
        self.assertIn("xcodebuild.log", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any("xcresulttool" in args for _, args in events))

    def test_failed_tests_with_a_bundle_still_validate_diagnostics(self):
        result = self.run_all(TEST_BUILD_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertTrue(any("xcresulttool" in args for _, args in events))
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

    def test_ensure_rerun_after_failure_runs_tooling_tests_again(self):
        result = self.run_all("--ensure", TEST_BUILD_FAILURE="1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        result = self.run_all("--ensure")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertEqual([args for name, args in events if name == "check"], [["--full", "--no-reuse"]] * 2)

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

    def test_new_runs_prune_older_evidence_beyond_the_retention_count(self):
        cache = self.repo / ".cache/test-all"
        seeded = [f"20260901-00000{index}-seeded{index}" for index in range(6)]
        for index, name in enumerate([*seeded, "notes"]):
            (cache / name / "TestResults.xcresult").mkdir(parents=True)
            os.utime(cache / name, ns=((index + 1) * 10**9,) * 2)
        (cache / "README").write_text("keep")
        result = self.run_all("--ensure")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_all("--verify")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        passing = Path(result.stdout.split("evidence: ")[-1].strip()).name
        self.assertEqual({path.name for path in cache.iterdir()},
                         {*seeded[2:], passing, "notes", "README"})
        result = self.run_all("--ensure", TEST_BUILD_FAILURE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(self.run_all(TEST_SKIPPED="1").returncode, 0)
        runs = {path.name for path in cache.iterdir()} - {"notes", "README"}
        failed = runs - {passing, *seeded}
        self.assertEqual(len(failed), 1)
        self.assertEqual(runs, {*seeded[3:], passing, *failed})

    def test_content_digest_catches_changes_hidden_from_git_status(self):
        self.assertEqual(self.run_all().returncode, 0)
        self.git("update-index", "--assume-unchanged", "source.txt")
        (self.repo / "source.txt").write_text("hidden change")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertNotEqual(self.run_all("--verify").returncode, 0)

    def test_ensure_rejects_unchecked_paths_before_running_tests(self):
        for flag in ("assume-unchanged", "skip-worktree"):
            with self.subTest(flag=flag):
                self.git("update-index", "--" + flag, "source.txt")
                try:
                    (self.repo / "source.txt").write_text("hidden change")
                    self.assertEqual(self.git("status", "--porcelain"), "")
                    result = self.run_all("--ensure")
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn("source.txt", result.stderr)
                    self.assertFalse((self.repo / ".cache").exists())
                finally:
                    (self.repo / "source.txt").write_text("original")
                    self.git("update-index", "--no-" + flag, "source.txt")

    def test_verify_rejects_development_evidence_with_unchecked_paths(self):
        self.git("update-index", "--assume-unchanged", "source.txt")
        (self.repo / "source.txt").write_text("hidden change")
        self.assertEqual(self.run_all().returncode, 0)
        result = self.run_all("--verify")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("source.txt", result.stderr)

    def test_ensure_rejects_paths_marked_unchecked_during_tests(self):
        result = self.run_all("--ensure", TEST_ASSUME_CHECKOUT="1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.report()["result"], "failed")

    def test_preflight_does_not_run_tests_or_write_evidence(self):
        result = self.run_all("--preflight")
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "check" or "test" in args for name, args in events))
        self.assertFalse((self.repo / ".cache").exists())

    def test_preflight_rejects_an_unsupported_toolchain(self):
        result = self.run_all("--preflight", TEST_XCODE_VERSION="26.5")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode 27+", result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "check" or "test" in args for name, args in events))
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
