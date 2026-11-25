"""Exercise the local test gate with isolated repositories and fake platform tools."""

from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid

import hang_guard
import service_guard


ROOT = Path(__file__).resolve().parents[2]
FAKE = r'''
import fcntl, json, os, pathlib, signal, subprocess, sys, time, uuid
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
    if os.environ.get('TEST_LOAD_SPIKE'):
        # Raise the load only until bin/test-all samples it while the macro tests run.
        spike = os.environ['TEST_LOAD_SPIKE'] + ' 1 1'
        (base / 'load.new').write_text(spike)
        os.replace(base / 'load.new', base / 'load')
        while spike not in (base / 'load-reads').read_text().splitlines():
            time.sleep(0.01)
        (base / 'load').unlink()
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
    timing = {'SiriPerformance': 'SiriLargeCatalogTests', 'OPMLPerformance': 'OPMLLargeImportTests'}
    performance = bundle.stem in timing
    fault = (os.environ.get('TEST_PERFORMANCE_FAULT')
             if bundle.stem == os.environ.get('TEST_PERFORMANCE_PHASE', 'SiriPerformance') else None)
    assert [arg for arg in args if arg.startswith(('-only-testing', '-skip-testing'))] == (
        ['-only-testing:PodHavenTests/' + timing[bundle.stem]] if performance
        else ['-skip-testing:PodHavenTests/' + suite for suite in timing.values()])
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
    for entry in filter(None, os.environ.get('TEST_HOST_TEMPORARY', '').split(os.pathsep)):
        pathlib.Path(entry).mkdir(parents=True, exist_ok=True)
    if os.environ.get('TEST_HOST_COVERAGE'):
        name = f'{str(uuid.uuid4()).upper()}-{os.getpid()}-{time.monotonic_ns():016X}'
        coverage = pathlib.Path(os.environ['TEST_HOST_COVERAGE']) / name
        coverage.mkdir()
        (coverage / 'run.profraw').write_bytes(b'profile')
        with (base / 'coverage').open('a') as stream:
            stream.write(coverage.name + '\n')
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
    fault = (os.environ.get('TEST_PERFORMANCE_FAULT')
             if bundle.stem == os.environ.get('TEST_PERFORMANCE_PHASE', 'SiriPerformance') else None)
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
    phase = pathlib.Path(args[args.index('--path') + 1]).stem
    fault = (os.environ.get('TEST_PERFORMANCE_FAULT')
             if phase == os.environ.get('TEST_PERFORMANCE_PHASE', 'SiriPerformance') else None)
    (output / 'StandardOutputAndStandardError.txt').write_text(
        'Main Thread Checker: invalid access' if fault == 'runtime' else 'Tests completed')
elif name == 'sample':
    path = pathlib.Path(args[args.index('-file') + 1])
    path.write_text('Analysis of sampling PodHaven (pid ' + args[0] + ')\n')
    if path.name.endswith('-2.sample.txt'):
        os.kill(int(args[0]), signal.SIGTERM)
elif name == 'check' and '--no-reuse' not in args and (base / 'check-passed').exists():
    print('Reused the application checks that passed earlier; bin/check --full --no-reuse runs them again.')
elif name in ('check', 'lint-swift-format'):
    while name == 'check' and os.environ.get('TEST_HOLD_TOOLING') and not pathlib.Path(
            os.environ['TEST_HOLD_TOOLING']).exists():
        time.sleep(0.05)
    for count in os.environ.get('TEST_PYTHON_COUNT', '1').split(','):
        print('Ran ' + count + ' test in 0.001s')
    print('OK (skipped=1)' if os.environ.get('TEST_PYTHON_SKIPPED') else 'OK')
    if os.environ.get('TEST_FAIL_STAGE') == name: sys.exit(23)
    if name == 'check': (base / 'check-passed').touch()
else:
    raise SystemExit('Unexpected command: ' + repr([name, args]))
'''

# Loaded at interpreter startup, so bin/test-all reads the load the fixture's load file sets.
LOAD = r'''
import os, pathlib
if 'TEST_ALL_FIXTURE' in os.environ:
    fixture = pathlib.Path(os.environ['TEST_ALL_FIXTURE'])

    def getloadavg():
        try:
            text = (fixture / 'load').read_text()
        except FileNotFoundError:
            text = '1.5 1.25 1.0'
        with (fixture / 'load-reads').open('a') as stream:
            stream.write(text.strip() + '\n')
        return tuple(map(float, text.split()))

    os.getloadavg = getloadavg
'''
BASE_LOAD = [1.5, 1.25, 1.0]
PHASES = ["tooling", "swift-lint", "macros", "xcodebuild", "siri-performance", "opml-performance"]
FOCUSED = ("/bin/sh", "-c", "echo held; read line; true")
TEST_HOST = "com.artisanalsoftware.PodHaven.debug"
APP_RESOLVED = "PodHaven.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
MACRO_RESOLVED = "PodHavenMacros/Package.resolved"


def pin(identity, **state):
    return {"identity": identity, "kind": "remoteSourceControl",
            "location": f"https://example.invalid/{identity}", "state": state}


MACRO_PINS = [pin("swift-syntax", branch="main", revision="a" * 40),
              pin("swift-tagged", branch="main", revision="b" * 40)]
APP_PINS = [pin("grdb.swift", branch="master", revision="c" * 40), *MACRO_PINS]


def write_package_pins(repo, app_pins=APP_PINS, macro_pins=MACRO_PINS):
    for name, pins in ((APP_RESOLVED, app_pins), (MACRO_RESOLVED, macro_pins)):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"originHash": name, "pins": pins, "version": 3}, indent=2) + "\n")


def make_container(home, name, identifier=TEST_HOST):
    """Create an app container in a disposable HOME and return its temporary directory."""
    container = home / "Library/Containers" / name
    (container / "Data/tmp").mkdir(parents=True, exist_ok=True)
    with (container / ".com.apple.containermanagerd.metadata.plist").open("wb") as stream:
        plistlib.dump({"MCMMetadataIdentifier": identifier}, stream)
    return container / "Data/tmp"


class TestAllTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven test all ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        for name in ("test-all", "check-swift-results", "_my_mac_lock.py", "_validation_slot.py"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        (self.base / "python").mkdir()
        (self.base / "python/sitecustomize.py").write_text(LOAD)
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
        write_package_pins(self.repo)
        (self.base / "home").mkdir()
        self.host_temporary = make_container(self.base / "home", "2D1F")
        self.env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                    "TEST_ALL_FIXTURE": str(self.base), "HOME": str(self.base / "home"),
                    "PYTHONPATH": str(self.base / "python")}
        for key in tuple(self.env):
            if key.startswith(("GIT_", "PODHAVEN_")) or key.startswith("TEST_") and key != "TEST_ALL_FIXTURE":
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
        return hang_guard.run([sys.executable, "-B", str(self.repo / "bin/test-all"), *args],
                              cwd=self.base, env={**self.env, **env}, text=True,
                              capture_output=True)

    def start(self, command, **env):
        process = hang_guard.start(command, cwd=self.base, env={**self.env, **env}, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(hang_guard.HANG_LIMIT, hang_guard.kill, (process,))
        watchdog.start()
        self.addCleanup(watchdog.cancel)
        self.addCleanup(hang_guard.stop, process)
        return process

    def start_all(self, repo, **env):
        return self.start([sys.executable, "-B", str(repo / "bin/test-all")], **env)

    def hold_focused_run(self, **env):
        """Start a focused run that holds a validation slot and the My Mac test lock until its input closes."""
        focused = self.start([sys.executable, "-B", str(ROOT / "bin/with-my-mac-lock"), *FOCUSED], **env)
        self.assertEqual(focused.stdout.readline(), "held\n")
        return focused

    def events(self):
        return [json.loads(line) for line in (self.base / "events").read_text().splitlines()]

    def report(self):
        return json.loads(next((self.repo / ".cache/test-all").glob("*/run.json")).read_text())

    def set_constants(self, **values):
        script = self.repo / "bin/test-all"
        text = script.read_text()
        for name, value in values.items():
            text, count = re.subn(rf"^{name} = .+$", f"{name} = {value}", text, flags=re.M)
            self.assertEqual(count, 1, name)
        script.write_text(text)

    def shorten_host_watch(self, quiet):
        self.set_constants(QUIET_LOG_SECONDS=quiet, SAMPLE_GAP_SECONDS=quiet / 5, POLL_SECONDS=quiet / 20)

    def test_complete_run_includes_separate_suites_and_records_revision(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertEqual([args for name, args in events if name == "check"], [["--full", "--no-reuse"]])
        self.assertTrue(any(name == "xcodebuild" and args[:1] == ["test"] for name, args in events))
        # bin/check --full runs the skill and helper suites, so bin/test-all doesn't run them again.
        self.assertFalse(any(name in ("test_skill.py", "test_helper.py") for name, _ in events))
        self.assertFalse((self.base / "shell-ran").exists())
        self.assertEqual(self.report()["checkout"]["revision"], self.git("rev-parse", "HEAD"))
        self.assertEqual(self.report()["checkout"]["status"], "")
        self.assertEqual(self.report()["result"], "passed")

    def test_timing_suites_run_separately_and_every_run_is_validated(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        builds = [args for name, args in events if name == "xcodebuild" and "test" in args]
        self.assertEqual([[arg for arg in args if arg.startswith(("-only-testing", "-skip-testing"))]
                          for args in builds],
                         [["-skip-testing:PodHavenTests/SiriLargeCatalogTests",
                           "-skip-testing:PodHavenTests/OPMLLargeImportTests"],
                          ["-only-testing:PodHavenTests/SiriLargeCatalogTests"],
                          ["-only-testing:PodHavenTests/OPMLLargeImportTests"]])
        bundles = [args[args.index("-resultBundlePath") + 1] for args in builds]
        self.assertEqual(len(set(bundles)), 3)
        for bundle in bundles:
            for command in (["get", "test-results", "summary"], ["get", "build-results"],
                            ["get", "test-results", "tests"], ["export", "diagnostics"]):
                self.assertTrue(any(name == "xcrun" and args[:1 + len(command)] == ["xcresulttool", *command]
                                    and args[args.index("--path") + 1] == bundle
                                    for name, args in events))
        artifacts = self.report()["artifacts"]
        for log in ("siri-performance", "opml-performance"):
            self.assertIn(f"{log}.log", artifacts)
            self.assertIn(f"{log}-validation.log", artifacts)

    def test_timing_suite_failures_never_leave_a_passing_report(self):
        for phase in ("SiriPerformance", "OPMLPerformance"):
            for fault in ("build", "missing-bundle", "failed-result", "empty", "skipped", "warning", "runtime"):
                with self.subTest(phase=phase, fault=fault):
                    shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                    result = self.run_all(TEST_PERFORMANCE_PHASE=phase, TEST_PERFORMANCE_FAULT=fault)
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
            process = hang_guard.start([sys.executable, "-B", str(repo / "bin/test-all")], cwd=self.base,
                                       env={**self.env, **env}, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            processes.append(process)
            return process

        def stop():
            if not released:
                os.close(writer)
            for process in processes:
                hang_guard.stop(process)

        self.addCleanup(stop)
        watchdog = threading.Timer(hang_guard.HANG_LIMIT, lambda: [hang_guard.kill(process) for process in processes])
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
        first_output, first_errors = hang_guard.finish(first)
        self.assertEqual(first.returncode, 0, first_output + first_errors)
        second_output, second_errors = hang_guard.finish(second)
        self.assertEqual(second.returncode, 0, second_output + second_errors)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        owners = [Path(args[args.index("-resultBundlePath") + 1]).parents[3]
                  for name, args in events if name == "xcodebuild" and "test" in args]
        self.assertEqual(owners, [self.repo.resolve()] * 3 + [other.resolve()] * 3)

    def test_a_third_concurrent_run_waits_for_one_of_the_two_validation_slots(self):
        repos = [self.repo, self.base / "second", self.base / "third"]
        for repo in repos[1:]:
            shutil.copytree(self.repo, repo, symlinks=True)
        gate = self.base / "tooling-gate"
        runs = []
        # Each run waits in its tooling phase, so the first two hold both slots at once.
        for repo in repos[:2]:
            runs.append(self.start_all(repo, TEST_HOLD_TOOLING=str(gate)))
            for line in runs[-1].stdout:
                if line.startswith("Running tooling;"):
                    break
            else:
                self.fail(f"The run in {repo} never started its tooling phase:\n" + runs[-1].stderr.read())
        third = self.start_all(repos[2], TEST_HOLD_TOOLING=str(gate))
        self.assertEqual(third.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=2), held by:\n")
        for number, (run, repo) in enumerate(zip(runs, repos), 1):
            self.assertRegex(third.stderr.readline(), rf"^  slot {number}: pid {run.pid} since .+: "
                                                      rf"bin/test-all in {re.escape(str(repo.resolve()))}\n$")
        gate.touch()
        for run in runs:
            output, errors = hang_guard.finish(run)
            self.assertEqual(run.returncode, 0, output + errors)
        output, errors = hang_guard.finish(third)
        self.assertEqual(third.returncode, 0, output + errors)
        self.assertRegex(errors, r"^Took validation slot [12]\n")
        self.assertEqual([args for name, args in self.events() if name == "check"], [["--full", "--no-reuse"]] * 3)

    def test_a_run_waits_for_its_validation_slot_before_the_my_mac_lock_and_every_phase(self):
        focused = self.hold_focused_run(PODHAVEN_VALIDATION_SLOTS="1")
        run = self.start_all(self.repo, PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(run.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=1), held by:\n")
        self.assertRegex(run.stderr.readline(), rf"^  slot 1: pid {focused.pid} since .+: /bin/sh -c 'echo held; ")
        self.assertFalse(any(name in ("check", "lint-swift-format") or "test" in args for name, args in self.events()))
        self.assertFalse((self.repo / ".cache").exists())
        focused.stdin.close()
        self.assertEqual(hang_guard.wait(focused), 0)
        output, errors = hang_guard.finish(run)
        self.assertEqual(run.returncode, 0, output + errors)
        self.assertEqual(errors, "Took validation slot 1\n")

    def test_runs_that_do_no_heavy_work_take_no_validation_slot(self):
        self.assertEqual(self.run_all().returncode, 0)
        focused = self.hold_focused_run(PODHAVEN_VALIDATION_SLOTS="1")
        for args in (("--preflight",), ("--verify",), ("--ensure",)):
            with self.subTest(args=args):
                result = self.run_all(*args, PODHAVEN_VALIDATION_SLOTS="1")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Waiting", result.stderr)
        focused.stdin.close()
        self.assertEqual(hang_guard.wait(focused), 0)

    def test_an_invalid_validation_slot_count_stops_before_any_phase(self):
        result = self.run_all(PODHAVEN_VALIDATION_SLOTS="none")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(result.stderr, "error: PODHAVEN_VALIDATION_SLOTS must be a positive integer, not 'none'\n")
        self.assertFalse((self.repo / ".cache").exists())

    def test_each_phase_records_the_host_load_and_its_peak_while_it_ran(self):
        self.set_constants(LOAD_SAMPLE_SECONDS=0.05)
        result = self.run_all(TEST_LOAD_SPIKE="1000000")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = self.report()
        self.assertEqual(report["result"], "passed")
        self.assertNotIn("saturation", report)
        self.assertNotIn("saturated", result.stderr)
        self.assertEqual(list(report["phases"]), PHASES)
        for name, phase in report["phases"].items():
            with self.subTest(phase=name):
                self.assertEqual(phase["result"], "passed")
                for sample in (phase["start"], phase["end"]):
                    self.assertEqual(sample["load_averages"], BASE_LOAD)
                    self.assertEqual(sample["cores"], os.cpu_count())
                    datetime.fromisoformat(sample["at"])
                self.assertLessEqual(phase["start"]["at"], phase["end"]["at"])
                # Only a sample taken while the macro tests ran saw the load they raised.
                self.assertEqual(phase["peak_load_1m"], 1000000 if name == "macros" else BASE_LOAD[0])
                self.assertEqual(phase["saturated"], name == "macros")

    def test_a_failure_while_the_host_is_saturated_is_flagged_and_still_fails(self):
        (self.base / "load").write_text(f"{2 * os.cpu_count() + 0.5} 1 1")
        for phase, env in (("tooling", {"TEST_FAIL_STAGE": "check"}),
                           ("macros", {"TEST_MACRO_WARNING": "1"}),
                           ("xcodebuild", {"TEST_PERFORMANCE_PHASE": "TestResults",
                                           "TEST_PERFORMANCE_FAULT": "warning"})):
            with self.subTest(phase=phase):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all("--ensure", **env)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                report = self.report()
                self.assertEqual(report["result"], "failed")
                self.assertEqual(list(report["phases"]), PHASES[:PHASES.index(phase) + 1])
                self.assertEqual(report["phases"][phase]["result"], "failed")
                self.assertTrue(report["phases"][phase]["saturated"])
                self.assertEqual(report["saturation"],
                                 f"The host was saturated during {phase}: its 1-minute load peaked at "
                                 f"{2 * os.cpu_count() + 0.5}, above twice its {os.cpu_count()} cores, "
                                 "so this failure may be load-induced.")
                self.assertTrue(result.stderr.endswith(report["saturation"] + "\n"), result.stderr)
                self.assertNotEqual(self.run_all("--verify").returncode, 0)
                self.assertNotEqual(self.run_all("--ensure", **env).returncode, 0)

    def test_a_failure_on_a_host_at_most_twice_its_core_count_is_not_flagged(self):
        (self.base / "load").write_text(f"{2 * os.cpu_count()} 1 1")
        result = self.run_all(TEST_MACRO_WARNING="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = self.report()
        self.assertEqual(report["phases"]["macros"]["result"], "failed")
        self.assertEqual(report["phases"]["macros"]["peak_load_1m"], 2 * os.cpu_count())
        self.assertFalse(report["phases"]["macros"]["saturated"])
        self.assertNotIn("saturation", report)
        self.assertNotIn("saturated", result.stderr)

    def test_stalled_test_host_is_sampled_twice_without_ending_the_run(self):
        self.shorten_host_watch(1)
        for bundle, log in (("TestResults", "xcodebuild"), ("SiriPerformance", "siri-performance"),
                            ("OPMLPerformance", "opml-performance")):
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

    def test_run_under_the_lock_command_reuses_its_lock_and_validation_slot(self):
        # With one slot, a run that waited for another would wait on its own holder forever.
        result = hang_guard.run([sys.executable, "-B", str(ROOT / "bin/with-my-mac-lock"),
                                 sys.executable, "-B", str(self.repo / "bin/test-all")],
                                cwd=self.base, env={**self.env, "PODHAVEN_VALIDATION_SLOTS": "1"}, text=True,
                                capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Waiting", result.stderr)

    def test_entries_tests_leave_in_the_test_host_temporary_directory_fail_the_run(self):
        (self.host_temporary / "earlier").mkdir()
        other_app = make_container(self.base / "home", "7C9A", "com.example.Other")
        result = self.run_all(TEST_HOST_TEMPORARY=os.pathsep.join([
            str(self.host_temporary / "TemporaryItems"),
            str(self.host_temporary / "com.artisanalsoftware.PodHaven.debug.savedState"),
            str(other_app / "other-app-file")]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        shutil.rmtree(self.repo / ".cache")
        result = self.run_all(TEST_HOST_TEMPORARY=os.pathsep.join([
            str(self.host_temporary / "left-by-a-test"), str(self.host_temporary / "also-left")]))
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("also-left, left-by-a-test", result.stderr)
        self.assertIn(str(self.host_temporary), result.stderr)
        self.assertNotIn("earlier", result.stderr)
        self.assertEqual(self.report()["result"], "failed")

    def test_coverage_directories_are_removed_once_the_run_that_made_them_ends(self):
        data = self.host_temporary.parent
        ended = subprocess.Popen([sys.executable, "-c", ""])
        ended.wait()
        running = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"])
        self.addCleanup(running.wait)
        self.addCleanup(running.kill)

        def coverage(pid):
            return data / f"{str(uuid.uuid4()).upper()}-{pid}-00000C3544C8360D"

        finished, live, reused, file = (coverage(ended.pid), coverage(running.pid), coverage(running.pid),
                                        coverage(ended.pid))
        for path in (finished, live, reused, data / "Library", data / finished.name[:-1]):
            path.mkdir()
        (finished / "run.profraw").write_bytes(b"profile")
        file.write_text("not a directory")
        before_running = time.time() - 3600
        os.utime(reused, (before_running, before_running))
        kept = {"tmp", "Library", finished.name[:-1], file.name, live.name}
        for failure in ("", "1"):
            with self.subTest(failure=bool(failure)):
                (self.base / "coverage").unlink(missing_ok=True)
                result = self.run_all(TEST_HOST_COVERAGE=str(data), TEST_BUILD_FAILURE=failure)
                self.assertEqual(result.returncode != 0, bool(failure), result.stdout + result.stderr)
                made = (self.base / "coverage").read_text().split()
                self.assertEqual(len(made), 1 if failure else 3)
                self.assertEqual({path.name for path in data.iterdir()}, kept)

    def test_missing_test_host_container_fails_the_run(self):
        shutil.rmtree(self.base / "home/Library")
        result = self.run_all()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("com.artisanalsoftware.PodHaven.debug", result.stderr)
        self.assertEqual(self.report()["result"], "failed")

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
        # The tooling log holds one count per suite, so an empty suite fails even before others that ran.
        for counts in ("0", "0,1"):
            with self.subTest(counts=counts):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all(TEST_PYTHON_COUNT=counts)
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

    def test_tooling_failure_stops_before_swift_build(self):
        result = self.run_all(TEST_FAIL_STAGE="check")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.report()["result"], "failed")
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "xcodebuild" and "test" in args for name, args in events))

    def test_macro_package_pins_that_differ_from_the_app_stop_before_tests(self):
        write_package_pins(self.repo, macro_pins=[
            pin("swift-syntax", branch="main", revision="d" * 40), MACRO_PINS[1],
            pin("swift-macro-only", version="1.0.0", revision="e" * 40)])
        result = self.run_all()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("swift-syntax (macros main dddddddddddd, app main aaaaaaaaaaaa)", result.stderr)
        self.assertIn("swift-macro-only (macros 1.0.0 eeeeeeeeeeee, app none)", result.stderr)
        self.assertNotIn("swift-tagged", result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        self.assertFalse(any(name == "check" or "test" in args for name, args in events))
        self.assertFalse((self.repo / ".cache").exists())

    def test_unreadable_package_pins_stop_before_tests(self):
        for name, contents in ((MACRO_RESOLVED, None), (APP_RESOLVED, "{}"), (MACRO_RESOLVED, "not json")):
            with self.subTest(name=name, contents=contents):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                write_package_pins(self.repo)
                path = self.repo / name
                if contents is None:
                    path.unlink()
                else:
                    path.write_text(contents)
                result = self.run_all()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(f"Could not read package pins from {name}", result.stderr)
                self.assertFalse((self.repo / ".cache").exists())

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

    def test_reuse_finds_an_older_pass_behind_newer_runs_it_cannot_reuse(self):
        cache = self.repo / ".cache/test-all"
        self.assertEqual(self.run_all().returncode, 0)
        (passing,) = cache.iterdir()
        self.assertNotEqual(self.run_all(TEST_SKIPPED="1").returncode, 0)
        (self.repo / "source.txt").write_text("dirty")
        self.assertEqual(self.run_all().returncode, 0)
        (self.repo / "source.txt").write_text("original")
        (cache / "29991231-235959-interrupted").mkdir()
        self.assertEqual(len(list(cache.iterdir())), 4)
        result = self.run_all("--verify")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(Path(result.stdout.split("evidence: ")[-1].strip()).name, passing.name)
        result = self.run_all("--ensure", TEST_BUILD_FAILURE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(list(cache.iterdir())), 4)
        (passing / "run.json").unlink()
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
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
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
