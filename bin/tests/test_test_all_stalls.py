"""Exercise how bin/test-all watches an xcodebuild test phase for a build or test host that stops making progress."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import sys
import time
import unittest

import hang_guard
import service_guard
from test_test_all import FAKE, TestAllFixture


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


class TestAllStallTests(TestAllFixture):

    def shorten_build_watch(self, stall):
        self.set_constants(BUILD_STALL_SECONDS=stall, BUILD_IDLE_CPU_SECONDS=stall / 2,
                           BUILD_POLL_SECONDS=stall / 10, STOP_SECONDS=stall, POLL_SECONDS=stall / 20)

    def install_fake(self, name):
        path = self.commands / name
        path.write_text(f"#!{sys.executable}\n" + FAKE)
        path.chmod(0o755)

    def wait_for_end(self, pid):
        deadline = time.monotonic() + hang_guard.HANG_LIMIT
        while alive(pid):
            self.assertLess(time.monotonic(), deadline, f"Process {pid} outlived bin/test-all")
            time.sleep(0.05)

    def test_a_build_that_stalls_is_sampled_and_stopped_with_every_process_it_started(self):
        self.shorten_build_watch(1)
        lock = self.base / "home/.cache/podhaven/my-mac-tests.lock"
        # An xcodebuild that ignores the interrupt is killed instead.
        for bundle, log, mode in (("TestResults", "xcodebuild", "stall"),
                                  ("SiriPerformance", "siri-performance", "deaf-stall")):
            with self.subTest(phase=log, mode=mode):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                (self.base / "events").unlink(missing_ok=True)
                result = self.run_all(TEST_BUILD_MODE=f"{bundle}:{mode}")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                stalled = [int(pid) for pid in (self.base / "build-stall").read_text().split()]
                output = next((self.repo / ".cache/test-all").iterdir()).resolve()
                sampled = {int(args[0]): Path(args[args.index("-file") + 1])
                           for name, args in self.events() if name == "sample"}
                self.assertEqual(sorted(sampled), sorted(stalled), result.stderr)
                self.assertEqual(sorted(sampled.values()), sorted(output.glob("*.sample.txt")))
                for pid, path in sampled.items():
                    self.assertRegex(path.name, rf"^{log}-build-.+-{pid}\.sample\.txt$")
                report = self.report()
                self.assertEqual(list(report["phases"])[-1], log)
                self.assertEqual(report["phases"][log]["result"], "failed")
                self.assertEqual(report["result"], "failed")
                self.assertIn(f"xcodebuild stalled before its tests started ({log})", report["error"])
                for path in sampled.values():
                    self.assertIn(f"Build sample: {path}", report["error"])
                    self.assertIn(f"Build sample: {path}", result.stderr.split("error: ")[-1])
                self.assertEqual("** BUILD INTERRUPTED **" in (output / f"{log}.log").read_text(), mode == "stall")
                # Nothing the build started outlives it to hold the run's locks, as the build service held this one.
                for pid in stalled:
                    self.wait_for_end(pid)
                with lock.open("a") as stream:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_a_slow_build_that_keeps_logging_or_its_processes_busy_is_not_stopped(self):
        self.shorten_build_watch(1)
        self.install_fake("ps")
        for mode in ("logging", "busy"):
            with self.subTest(mode=mode):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all(TEST_BUILD_MODE=f"TestResults:{mode}", TEST_BUILD_SECONDS="3")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(list((self.repo / ".cache").rglob("*.sample.txt")), [])
                self.assertEqual(self.report()["result"], "passed")

    def test_a_quiet_wait_before_xcodebuild_starts_or_once_its_test_host_runs_is_no_build_stall(self):
        self.shorten_build_watch(1)
        for bundle, mode in (("TestResults", "starting"), ("SiriPerformance", "testing")):
            with self.subTest(mode=mode):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all(TEST_BUILD_MODE=f"{bundle}:{mode}", TEST_BUILD_SECONDS="3")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(list((self.repo / ".cache").rglob("*.sample.txt")), [])
                self.assertEqual(self.report()["result"], "passed")

    def test_stalled_test_host_is_sampled_twice_without_ending_the_run(self):
        self.shorten_host_watch(1)
        # A build still watched once XCTest names its host would stop the run before the host is sampled.
        self.shorten_build_watch(0.5)
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


if __name__ == "__main__":
    unittest.main()
