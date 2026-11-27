"""Exercise bin/test-all's lane on a second Mac, which a fake ssh stands in for on this Mac.

The fake runs each remote command in a session of its own, with the host's own home folder, its fakes for the
commands that only the host's desktop session takes, and none of this Mac's test settings except those spelled
TEST_REMOTE_*, which reach the host without REMOTE_. Like a real client, it relays its input to the session and
closes the session's input when it exits."""

import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import unittest

import hang_guard
import service_guard
from test_test_all import PHASES, TestAllFixture, make_container
from test_validation_slot import BIN, driver

SSH = r'''
import json, os, pathlib, subprocess, sys, threading
base = pathlib.Path(os.environ['TEST_ALL_FIXTURE'])
args = sys.argv[1:]
with (base / 'events').open('a') as stream:
    stream.write(json.dumps(['ssh', args]) + '\n')
index = 0
while args[index].startswith('-'):
    index += 2 if len(args[index]) == 2 and args[index][1] in 'BbcDEeFIiJLlmOoPpQRSWw' else 1
host, command = args[index], ' '.join(args[index + 1:])
if os.environ.get('TEST_SSH_UNREACHABLE'):
    print(f'ssh: connect to host {host} port 22: Host is down', file=sys.stderr)
    sys.exit(255)
env = {key: value for key, value in os.environ.items() if not key.startswith('TEST_') or key == 'TEST_ALL_FIXTURE'}
env.update({'TEST_' + key[len('TEST_REMOTE_'):]: value for key, value in os.environ.items()
            if key.startswith('TEST_REMOTE_')})
env.update(HOME=str(base / 'remote-home'), PATH=str(base / 'remote-commands') + os.pathsep + os.environ['PATH'])
# A connection that fails once the run there starts: the client exits, and the session's streams close with it.
lost = os.environ.get('TEST_SSH_CONNECTION_LOST') and command.startswith('lockf ')
streams = subprocess.PIPE if lost else None
session = subprocess.Popen(['/bin/zsh', '-c', command], cwd=env['HOME'], env=env, stdin=subprocess.PIPE,
                           stdout=streams, stderr=streams, start_new_session=True)
# A dropped connection that never closed: the session's input stays open and hears nothing more.
dropped = os.environ.get('TEST_SSH_SILENT_DROP') and command.startswith('lockf ')


def forward():
    try:
        while chunk := os.read(0, 1024):
            if not dropped:
                session.stdin.write(chunk)
                session.stdin.flush()
        if not dropped:
            session.stdin.close()
    except OSError:
        pass


threading.Thread(target=forward, daemon=True).start()
if lost:
    for line in session.stderr:
        sys.stderr.buffer.write(line)
        sys.stderr.buffer.flush()
        if b'Running tooling;' in line:
            break
    print(f'Connection to {host} closed by remote host.', file=sys.stderr, flush=True)
    sys.exit(255)
sys.exit(session.wait())
'''
SUDO = r'''
import os, sys
args = sys.argv[1:]
while args[0].startswith('-'):
    args = args[2:] if args[0] == '-u' else args[1:]
os.execvp(args[0], args)
'''
LAUNCHCTL = r'''
import os, sys
args = sys.argv[1:]
assert args[:2] == ['asuser', str(os.getuid())], args
if os.environ.get('TEST_DESKTOP_FAILURE'):
    print('Could not switch to audit session 0x186a1: 1: Operation not permitted', file=sys.stderr)
    sys.exit(1)
os.execvp(args[2], args[2:])
'''
FDESETUP = r'''
import os, sys
assert sys.argv[1:] == ['isactive'], sys.argv
sys.exit(0 if os.environ.get('TEST_FILEVAULT') else 1)
'''
HOST = "mini"
# Holds the My Mac test lock as HOLDER until a line arrives on standard input.
MY_MAC_LOCK = r'''
import sys
sys.path.insert(0, sys.argv[1])
from _my_mac_lock import my_mac_lock
with my_mac_lock(sys.argv[2]):
    print("held", flush=True)
    sys.stdin.readline()
'''


class SecondMacTests(TestAllFixture):
    def setUp(self):
        super().setUp()
        self.remote_home = self.base / "remote-home"
        self.remote_temporary = make_container(self.remote_home, "9E4B")
        commands = self.base / "remote-commands"
        commands.mkdir()
        for path, script in ((self.commands / "ssh", SSH), (commands / "sudo", SUDO),
                             (commands / "launchctl", LAUNCHCTL), (commands / "fdesetup", FDESETUP)):
            path.write_text(f"#!{sys.executable}\n" + script)
            path.chmod(0o755)
        lanes = self.remote_home / "Library/Caches/podhaven/test-lanes"
        self.lane, self.mirror = lanes / "lane-1", lanes / "mirror.git"
        self.lock = self.remote_home / "Library/Application Support/home-infra/mac-mini/scheduled-jobs.lock"
        self.git("config", "podhaven.testHost", HOST)
        # The test's own folder, which the test user owns, stands in for the console the user is logged in at.
        self.set_constants("_test_lane_host.py", CONSOLE=repr(str(self.base)))
        self.commit("Log in at the second Mac's desktop")
        # The host's side ends on its own once its client goes, as it would on another Mac.
        self.addCleanup(self.wait_for_free_lane)

    def wait_for_free_lane(self, seconds=hang_guard.HANG_LIMIT):
        if self.lock.exists():
            subprocess.run(["lockf", "-k", "-t", str(seconds), str(self.lock), "true"], check=True)

    def lane_free(self):
        return subprocess.run(["lockf", "-s", "-k", "-t", "0", str(self.lock), "true"]).returncode == 0

    def owners(self):
        """Return the checkout that ran each xcodebuild test, in order."""
        return [Path(args[args.index("-resultBundlePath") + 1]).parents[3]
                for name, args in self.events() if name == "xcodebuild" and "test" in args]

    def lane_attempts(self):
        return [args for name, args in self.events() if name == "ssh" and args[-1].startswith("lockf ")]

    def evidence(self):
        return sorted((path.resolve() for path in (self.repo / ".cache/test-all").iterdir() if path.is_dir()),
                      key=lambda path: path.stat().st_mtime_ns)

    def hold(self, name):
        """Return a FIFO whose readers wait until close_hold closes it, as the fake xcodebuild's TEST_HOLD_FIFO does."""
        gate = self.base / name
        os.mkfifo(gate)
        reader = os.open(gate, os.O_RDONLY | os.O_NONBLOCK)
        writer = os.open(gate, os.O_WRONLY)
        os.close(reader)
        self.addCleanup(self.close_hold, writer)
        return gate, writer

    def close_hold(self, writer):
        try:
            os.close(writer)
        except OSError:
            pass

    def started_tests(self, process):
        for line in process.stdout:
            if line.startswith("Running xcodebuild;"):
                return
        self.fail("The run never started its My Mac tests:\n" + process.stderr.read())

    def queue(self):
        return sorted((self.base / "home/.cache/podhaven/validation-queue").iterdir())

    def hold_slot(self, holder):
        """Start a run that holds this Mac's only validation slot until its input closes."""
        process = self.start(driver(holder), PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(process.stdout.readline(), f"held {holder}\n")
        return process

    def release(self, process):
        process.stdin.close()
        self.assertEqual(hang_guard.wait(process), 0)

    def hold_second_mac(self):
        """Start a run that holds the second Mac's lane until the returned writer closes."""
        other = self.base / "other"
        shutil.copytree(self.repo, other, symlinks=True)
        gate, writer = self.hold("remote-gate")
        remote = self.start_all(other, TEST_REMOTE_HOLD_FIFO=str(gate))
        self.started_tests(remote)
        return remote, writer

    def finish_second_mac(self, remote, writer):
        self.close_hold(writer)
        output, errors = hang_guard.finish(remote)
        self.assertEqual(remote.returncode, 0, output + errors)

    def wait_for_both_lanes(self, **env):
        """Hold both Macs' lanes, then start a run that waits for either and a later focused run that waits for this
        Mac's only validation slot, and return the holders and the waiting runs."""
        remote, writer = self.hold_second_mac()
        holder = self.hold_slot("holder")
        waiter = self.start_all(self.repo, PODHAVEN_VALIDATION_SLOTS="1", **env)
        self.assertTrue(waiter.stderr.readline().startswith("Waiting for the second Mac's lane, held by "))
        later = self.start([sys.executable, "-B", str(BIN / "with-my-mac-lock"), "/bin/echo", "ran"],
                           PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(later.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=1), held by:\n")
        self.assertRegex(later.stderr.readline(), rf"^  slot 1: pid {holder.pid} since .+: holder\n$")
        # The run waiting for both lanes holds the earlier of the queue's two tickets.
        self.assertEqual(len(self.queue()), 2)
        self.assertEqual(later.stderr.readline(), "Queued behind 1 earlier waiting run\n")
        return remote, writer, holder, waiter, later

    def assert_took_slot(self, process, output):
        self.assertEqual(process.stderr.read(), "Took validation slot 1\n")
        self.assertEqual(process.stdout.read(), output)
        self.assertEqual(hang_guard.wait(process), 0)
        self.assertEqual(self.queue(), [])

    def test_a_clean_run_goes_to_the_second_mac_and_its_evidence_counts_here(self):
        # A run there needs neither this Mac's validation slot nor its My Mac test lock.
        focused = self.hold_focused_run(PODHAVEN_VALIDATION_SLOTS="1")
        result = self.run_all(PODHAVEN_VALIDATION_SLOTS="1")
        focused.stdin.close()
        self.assertEqual(hang_guard.wait(focused), 0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Waiting", result.stderr)
        self.assertEqual(self.owners(), [self.lane.resolve()] * 3)
        (output,) = self.evidence()
        self.assertIn(f"Test evidence: {output}\n", result.stdout)
        self.assertIn(f"Running tooling; log: {output}/tooling.log\n", result.stdout)
        self.assertTrue(result.stdout.endswith(f"All tests passed on the second Mac, {HOST}. Evidence: {output}\n"),
                        result.stdout)
        self.assertIn(f"Running on the second Mac, {os.uname().nodename}: {self.lane}/bin/test-all at "
                      f"{self.git('rev-parse', 'HEAD')}\n", result.stderr)
        self.assertRegex(self.lock.read_text(),
                         rf"^PodHaven bin/test-all from .+ for {self.git('rev-parse', 'HEAD')[:12]}, pid \d+, since ")
        report = self.report()
        self.assertEqual(report["result"], "passed")
        self.assertEqual(report["remote"]["host"], HOST)
        self.assertEqual(report["remote"]["result"], "passed")
        self.assertEqual(report["remote"]["checkout"]["revision"], self.git("rev-parse", "HEAD"))
        self.assertEqual(list(report["phases"]), PHASES)
        attempts = len(self.lane_attempts())
        for args in (("--verify",), ("--ensure", "--revision", self.git("rev-parse", "HEAD"))):
            with self.subTest(args=args):
                result = self.run_all(*args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stdout, f"Verified full local test evidence: {output}\n")
        self.assertEqual(len(self.lane_attempts()), attempts)

    def test_two_runs_started_together_use_both_macs(self):
        other = self.base / "other"
        shutil.copytree(self.repo, other, symlinks=True)
        gate, writer = self.hold("remote-gate")
        first = self.start_all(self.repo, TEST_REMOTE_HOLD_FIFO=str(gate))
        self.started_tests(first)
        second = self.start_all(other)
        output, errors = hang_guard.finish(second)
        self.assertEqual(second.returncode, 0, output + errors)
        self.assertRegex(output, r"^Running on this Mac: the second Mac's lane is held by PodHaven bin/test-all from "
                                 r".+, pid \d+, since .+, and this Mac's is free\n")
        self.close_hold(writer)
        output, errors = hang_guard.finish(first)
        self.assertEqual(first.returncode, 0, output + errors)
        self.assertEqual(self.owners(), [self.lane.resolve()] + [other.resolve()] * 3 + [self.lane.resolve()] * 2)

    def test_a_run_waiting_for_both_lanes_takes_whichever_frees_first(self):
        self.set_constants(REMOTE_POLL_SECONDS=0.2)
        self.commit("Poll the second Mac often")
        other = self.base / "other"
        shutil.copytree(self.repo, other, symlinks=True)
        for remote_first in (False, True):
            with self.subTest(remote_first=remote_first):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                gate, writer = self.hold(f"gate-{remote_first}")
                remote = self.start_all(other, TEST_REMOTE_HOLD_FIFO=str(gate))
                self.started_tests(remote)
                focused = self.hold_focused_run()
                waiter = self.start_all(self.repo)
                self.assertRegex(waiter.stderr.readline(),
                                 r"^Waiting for the second Mac's lane, held by PodHaven bin/test-all from .+, or this "
                                 r"Mac's, held by:\n$")
                self.assertRegex(waiter.stderr.readline(), rf"^  validation slot 1: pid {focused.pid} since ")
                self.assertEqual(waiter.stderr.readline(), "  validation slot 2: free\n")
                self.assertRegex(waiter.stderr.readline(), rf"^  My Mac test lock: pid {focused.pid} since ")
                if remote_first:
                    self.close_hold(writer)
                else:
                    focused.stdin.close()
                output, errors = hang_guard.finish(waiter)
                self.assertEqual(waiter.returncode, 0, output + errors)
                self.assertEqual("remote" in self.report(), remote_first, output)
                self.close_hold(writer)
                focused.stdin.close()
                self.assertEqual(hang_guard.wait(focused), 0)
                output, errors = hang_guard.finish(remote)
                self.assertEqual(remote.returncode, 0, output + errors)

    def test_a_run_waiting_for_both_lanes_takes_a_freed_slot_before_a_later_waiter(self):
        # The run waits in its tooling phase once it starts here, until the test sees it hold the slot.
        tooling = self.base / "tooling-gate"
        remote, writer, holder, waiter, later = self.wait_for_both_lanes(TEST_HOLD_TOOLING=str(tooling))
        self.release(holder)
        self.assertRegex(later.stderr.readline(), rf"^Validation slot 1 is now held by pid {waiter.pid} since .+: "
                                                  rf"bin/test-all in {re.escape(str(self.repo.resolve()))}\n$")
        self.assertEqual(later.stderr.readline(), "Next in line for a validation slot\n")
        tooling.touch()
        output, errors = hang_guard.finish(waiter)
        self.assertEqual(waiter.returncode, 0, output + errors)
        self.assertRegex(output, r"^Running on this Mac: the second Mac's lane is held by PodHaven bin/test-all from "
                                 r".+, and this Mac's is free\n")
        self.assertNotIn("remote", self.report())
        self.assert_took_slot(later, "ran\n")
        self.finish_second_mac(remote, writer)

    def test_a_run_waiting_for_both_lanes_leaves_the_queue_when_the_second_mac_frees_first(self):
        self.set_constants(REMOTE_POLL_SECONDS=0.2)
        self.commit("Poll the second Mac often")
        remote, writer, holder, waiter, later = self.wait_for_both_lanes()
        self.close_hold(writer)
        self.assertEqual(later.stderr.readline(), "Next in line for a validation slot\n")
        output, errors = hang_guard.finish(waiter)
        self.assertEqual(waiter.returncode, 0, output + errors)
        self.assertEqual(self.report()["remote"]["host"], HOST)
        self.assertEqual(len(self.queue()), 1)
        self.release(holder)
        self.assert_took_slot(later, "ran\n")
        self.finish_second_mac(remote, writer)

    def test_a_run_waiting_for_both_lanes_leaves_the_queue_when_it_stops(self):
        remote, writer, holder, waiter, later = self.wait_for_both_lanes()
        os.kill(waiter.pid, signal.SIGKILL)
        self.assertEqual(hang_guard.wait(waiter), -signal.SIGKILL)
        self.assertEqual(later.stderr.readline(), "Next in line for a validation slot\n")
        self.assertEqual(len(self.queue()), 1)
        # A run that is interrupted removes its own ticket as it exits.
        interrupted = self.start_all(self.repo, PODHAVEN_VALIDATION_SLOTS="1")
        self.assertTrue(interrupted.stderr.readline().startswith("Waiting for the second Mac's lane, held by "))
        self.assertEqual(len(self.queue()), 2)
        os.kill(interrupted.pid, signal.SIGINT)
        self.assertNotEqual(hang_guard.wait(interrupted), 0)
        self.assertEqual(len(self.queue()), 1)
        self.release(holder)
        self.assert_took_slot(later, "ran\n")
        self.finish_second_mac(remote, writer)

    def test_a_run_waiting_for_both_lanes_reports_each_new_holder(self):
        self.set_constants(REMOTE_POLL_SECONDS=0.2)
        self.commit("Poll the second Mac often")
        remote, writer = self.hold_second_mac()
        first = self.hold_slot("first")
        second = self.start(driver("second"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(second.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=1), held by:\n")
        self.assertRegex(second.stderr.readline(), rf"^  slot 1: pid {first.pid} since .+: first\n$")
        # The run waits in its tooling phase once it starts here, until the test sees it hold the slot.
        tooling = self.base / "tooling-gate"
        waiter = self.start_all(self.repo, PODHAVEN_VALIDATION_SLOTS="1", TEST_HOLD_TOOLING=str(tooling))
        self.assertRegex(waiter.stderr.readline(), r"^Waiting for the second Mac's lane, held by PodHaven bin/test-all "
                                                   r"from .+, or this Mac's, held by:\n$")
        self.assertRegex(waiter.stderr.readline(), rf"^  validation slot 1: pid {first.pid} since .+: first\n$")
        self.assertEqual(waiter.stderr.readline(), "  My Mac test lock: free\n")
        self.assertEqual(waiter.stderr.readline(), "Queued behind 1 earlier waiting run\n")
        nightly = "the host's nightly tests, pid 1, since 2026-11-27 03:00 PST"
        self.lock.write_text(nightly + "\n")
        self.assertEqual(waiter.stderr.readline(), f"The second Mac's lane is now held by {nightly}\n")
        self.release(first)
        self.assertEqual(second.stdout.readline(), "held second\n")
        self.assertRegex(waiter.stderr.readline(), rf"^Validation slot 1 is now held by pid {second.pid} since .+: "
                                                   r"second\n$")
        self.assertEqual(waiter.stderr.readline(), "Next in line for a validation slot\n")
        lock = self.start([sys.executable, "-B", "-c", MY_MAC_LOCK, str(BIN), "a focused run"])
        self.assertEqual(lock.stdout.readline(), "held\n")
        self.assertRegex(waiter.stderr.readline(),
                         rf"^The My Mac test lock is now held by pid {lock.pid} since .+: a focused run\n$")
        # This Mac's lane stays busy while its My Mac test lock is held, and the run keeps its place meanwhile.
        self.release(second)
        third = self.start(driver("third", "/bin/echo", "ran"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(third.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=1), held by:\n")
        self.assertEqual(third.stderr.readline(), "  slot 1: free\n")
        self.assertEqual(third.stderr.readline(), "Queued behind 1 earlier waiting run\n")
        self.release(lock)
        self.assertRegex(third.stderr.readline(), rf"^Validation slot 1 is now held by pid {waiter.pid} since ")
        self.assertEqual(third.stderr.readline(), "Next in line for a validation slot\n")
        tooling.touch()
        output, errors = hang_guard.finish(waiter)
        self.assertEqual(waiter.returncode, 0, output + errors)
        self.assertTrue(output.startswith(f"Running on this Mac: the second Mac's lane is held by {nightly}, and this "
                                          "Mac's is free\n"), output)
        self.assert_took_slot(third, "held third\nran\n")
        self.finish_second_mac(remote, writer)

    def test_runs_over_uncommitted_changes_stay_on_this_mac(self):
        (self.repo / "new.txt").write_text("uncommitted")
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(result.stdout.startswith(
            "Running on this Mac: the checkout has uncommitted changes, and the second Mac runs only commits\n"))
        self.assertFalse(any(name == "ssh" for name, _ in self.events()))
        self.assertEqual(set(self.owners()), {self.repo.resolve()})

    def test_a_host_that_cannot_take_the_run_leaves_it_on_this_mac(self):
        for env, reason in (
                ({"TEST_SSH_UNREACHABLE": "1"},
                 f"it is unreachable: ssh: connect to host {HOST} port 22: Host is down"),
                ({"TEST_REMOTE_XCODE_VERSION": "27.1"}, "its Xcode is 'Xcode 27.1', not this Mac's 'Xcode 27.0'"),
                ({"TEST_REMOTE_SWIFT_VERSION": "6.5"},
                 "its Swift is 'swift-driver version: 1.168.6 Apple Swift version 6.5', not this Mac's "
                 "'swift-driver version: 1.168.6 Apple Swift version 6.4'"),
                ({"TEST_REMOTE_MACOS_VERSION": "27.1"}, "its macOS is '27.1', not this Mac's '27.0'"),
                ({"TEST_REMOTE_DESKTOP_FAILURE": "1"}, "its desktop session refused a command: Could not switch to "
                                                       "audit session 0x186a1: 1: Operation not permitted")):
            with self.subTest(reason=reason):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                (self.base / "events").unlink(missing_ok=True)
                result = self.run_all(**env)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(result.stdout.startswith(
                    f"Running on this Mac: the second Mac, {HOST}, can't run it: {reason}\n"), result.stdout)
                self.assertEqual(set(self.owners()), {self.repo.resolve()})
                self.assertEqual(self.lane_attempts(), [])

    def test_a_host_without_a_desktop_login_leaves_the_run_on_this_mac(self):
        # The root folder, which root owns, stands in for a console no one is logged in at.
        self.set_constants("_test_lane_host.py", CONSOLE=repr("/"))
        self.commit("Log out of the second Mac's desktop")
        for env, reason in (({}, "no one is logged in at its desktop"),
                            ({"TEST_REMOTE_FILEVAULT": "1"},
                             "no one is logged in at its desktop, and FileVault is on, so it may still be locked")):
            with self.subTest(reason=reason):
                shutil.rmtree(self.repo / ".cache", ignore_errors=True)
                result = self.run_all(**env)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(result.stdout.startswith(
                    f"Running on this Mac: the second Mac, {HOST}, can't run it: {reason}\n"), result.stdout)
                self.assertEqual(self.lane_attempts(), [])

    def test_a_mirror_that_cannot_take_the_commit_leaves_the_run_on_this_mac(self):
        # A damaged mirror refuses the push.
        self.mirror.mkdir(parents=True)
        (self.mirror / "HEAD").write_text("damaged")
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(result.stdout.startswith(
            f"Running on this Mac: the second Mac, {HOST}, can't run it: sending the commit to it failed: fatal: "
            "'Library/Caches/podhaven/test-lanes/mirror.git' does not appear to be a git repository\n"), result.stdout)
        self.assertEqual(set(self.owners()), {self.repo.resolve()})
        self.assertEqual(self.lane_attempts(), [])

    def test_a_signing_failure_there_asks_the_host_to_renew_and_runs_here(self):
        request = self.remote_home / "Library/Application Support/home-infra/mac-mini/signing-renewal-requested"
        result = self.run_all(TEST_REMOTE_SIGNING_FAILURE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Running on this Mac: the second Mac, {HOST}, couldn't sign the test host, so bin/test-all "
                      "asked it to renew its signing\n", result.stdout)
        self.assertTrue(request.exists())
        self.assertEqual(self.owners(), [self.lane.resolve()] + [self.repo.resolve()] * 3)
        attempt, local = self.evidence()
        report = json.loads((attempt / "run.json").read_text())
        self.assertEqual(report["result"], "failed")
        self.assertEqual(report["remote"]["host"], HOST)
        self.assertIn("No profiles for", (attempt / "xcodebuild.log").read_text())
        self.assertNotIn("remote", json.loads((local / "run.json").read_text()))
        result = self.run_all("--verify")
        self.assertEqual(result.stdout, f"Verified full local test evidence: {local}\n")

    def test_a_run_there_that_ends_without_a_report_runs_here(self):
        reason = f"the second Mac, {HOST}, ended its run with exit status 3 and no report"
        # A lane that can't be prepared sends no evidence.
        self.lane.parent.mkdir(parents=True)
        self.lane.write_text("not a checkout")
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Could not prepare the second Mac's lane: ", result.stderr)
        self.assertIn(f"Running on this Mac: {reason}\n", result.stdout)
        self.assertEqual(self.owners(), [self.repo.resolve()] * 3)
        self.assertEqual(len(self.evidence()), 1)
        self.assertNotIn("remote", self.report())
        # A run there that dies sends the logs it wrote, which come back without a report.
        self.lane.unlink()
        shutil.rmtree(self.repo / ".cache")
        (self.base / "events").unlink()
        result = self.run_all(TEST_REMOTE_KILL_GATE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Running on this Mac: {reason}\n", result.stdout)
        self.assertEqual(self.owners(), [self.repo.resolve()] * 3)
        attempt, local = self.evidence()
        report = json.loads((attempt / "run.json").read_text())
        self.assertEqual((report["result"], report["error"], report["remote"]), ("failed", reason, {"host": HOST}))
        self.assertTrue((attempt / "tooling.log").is_file())
        self.assertNotIn("remote", json.loads((local / "run.json").read_text()))
        self.assertEqual(self.run_all("--verify").stdout, f"Verified full local test evidence: {local}\n")

    def test_a_run_that_fails_there_fails_without_running_here(self):
        request = self.remote_home / "Library/Application Support/home-infra/mac-mini/signing-renewal-requested"
        result = self.run_all(TEST_REMOTE_BUILD_FAILURE="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        (output,) = self.evidence()
        self.assertTrue(result.stderr.endswith(
            f"error: bin/test-all failed on the second Mac; its evidence is in {output}\n"), result.stderr)
        self.assertIn("error: Swift tests or evidence validation failed (xcodebuild)\n", result.stderr)
        self.assertEqual(self.owners(), [self.lane.resolve()])
        self.assertFalse(request.exists())
        report = self.report()
        self.assertEqual((report["result"], report["remote"]["result"]), ("failed", "failed"))
        self.assertEqual(report["error"], "Swift tests or evidence validation failed (xcodebuild)")
        self.assertNotEqual(self.run_all("--verify").returncode, 0)

    def test_the_second_macs_run_samples_a_stalled_host_into_the_evidence_here(self):
        self.shorten_host_watch(1)
        self.commit("Watch the test host closely")
        result = self.run_all(TEST_REMOTE_HOST_STALL="TestResults")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        (output,) = self.evidence()
        host = (self.base / "stalled-host").read_text()
        samples = [output / f"xcodebuild-host-{host}-{index}.sample.txt" for index in (1, 2)]
        self.assertEqual(sorted(output.glob("*.sample.txt")), samples)
        for path in samples:
            self.assertIn(f"Test host sample: {path}", self.report()["error"])
            self.assertIn(f"Test host sample: {path}", result.stderr)
        self.assertNotIn(str(self.lane), self.report()["error"])

    def test_the_second_macs_run_checks_its_own_test_host_temporary_directory(self):
        result = self.run_all(TEST_REMOTE_HOST_TEMPORARY=str(self.remote_temporary / "left-by-a-test"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f"Tests left 1 new entries in {self.remote_temporary}: left-by-a-test", self.report()["error"])
        result = self.run_all(TEST_HOST_TEMPORARY=str(self.host_temporary / "left-here"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_the_lane_holds_only_the_commits_files_at_one_path(self):
        self.assertEqual(self.run_all().returncode, 0)
        (self.lane / "planted.txt").write_text("untracked")
        (self.lane / ".cache/planted").write_text("ignored")
        (self.lane / "source.txt").write_text("changed there")
        (self.repo / "source.txt").write_text("second")
        self.commit("Change the source")
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(set(self.owners()), {self.lane.resolve()})
        self.assertFalse((self.lane / "planted.txt").exists())
        self.assertFalse((self.lane / ".cache/planted").exists())
        self.assertEqual((self.lane / "source.txt").read_text(), "second")

    def test_the_lane_starts_from_the_same_default_branch_as_this_checkout(self):
        # bin/check's whitespace check reads only the changes since origin's default branch.
        def lane_default():
            return subprocess.run(["git", "rev-parse", "--verify", "--quiet", "refs/remotes/origin/HEAD"],
                                  cwd=self.lane, capture_output=True, text=True).stdout.strip()

        # The default branch's own commit, as a release from it tests, is the commit under test too.
        for base in (self.git("rev-parse", "HEAD~1"), self.git("rev-parse", "HEAD"), ""):
            with self.subTest(base=base):
                self.git("update-ref", *(("refs/remotes/origin/HEAD", base) if base
                                         else ("-d", "refs/remotes/origin/HEAD")))
                result = self.run_all()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Running on this Mac", result.stdout)
                self.assertEqual(lane_default(), base)

    def test_the_mirror_keeps_the_newest_commits_and_the_one_under_test(self):
        self.set_constants("_test_lane_host.py", MIRROR_REFS=1)
        commits = []
        for day in (1, 2, 3, 0):
            date = f"2026-11-0{day + 1}T12:00:00Z"
            commits.append(self.commit(f"Day {day}", GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date))
            result = self.run_all()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        refs = subprocess.check_output(["git", "for-each-ref", "--format=%(refname)", "refs/test-all/"],
                                       cwd=self.mirror, text=True).split()
        # The last run tested the oldest commit, which stays besides the newest.
        self.assertEqual(sorted(refs), sorted(f"refs/test-all/{commit}" for commit in (commits[2], commits[3])))

    def test_a_run_there_whose_connection_ends_stops_and_frees_the_lane(self):
        gate, _ = self.hold("remote-gate")
        run = self.start_all(self.repo, TEST_REMOTE_HOLD_FIFO=str(gate))
        self.started_tests(run)
        self.assertFalse(self.lane_free())
        # Only this Mac's side ends, as when its client loses the connection.
        os.kill(run.pid, 9)
        hang_guard.wait(run)
        self.wait_for_free_lane(60)
        self.assertTrue(self.lane_free())

    def test_a_connection_lost_during_a_run_there_runs_it_here(self):
        result = self.run_all(TEST_SSH_CONNECTION_LOST="1", TEST_REMOTE_HOLD_TOOLING=str(self.base / "never"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Connection to {HOST} closed by remote host.\n", result.stderr)
        self.assertIn(f"Running on this Mac: the connection to the second Mac, {HOST}, failed during its run\n",
                      result.stdout)
        self.assertEqual(self.owners(), [self.repo.resolve()] * 3)
        self.assertEqual(len(self.evidence()), 1)
        self.assertNotIn("remote", self.report())
        # The host heard its input end, so it stopped its run, which frees the lane.
        self.wait_for_free_lane(60)

    def test_heartbeats_keep_a_long_run_there_going_and_a_silent_drop_stops_it(self):
        self.set_constants("_test_lane.py", HEARTBEAT_SECONDS=0.1)
        self.set_constants("_test_lane_host.py", HEARTBEAT_TIMEOUT_SECONDS=1, STOP_GRACE_SECONDS=1)
        self.commit("Beat often")
        gate, writer = self.hold("remote-gate")
        run = self.start_all(self.repo, TEST_REMOTE_HOLD_FIFO=str(gate))
        self.started_tests(run)
        time.sleep(3)
        self.close_hold(writer)
        output, errors = hang_guard.finish(run)
        self.assertEqual(run.returncode, 0, output + errors)
        self.assertIn("remote", self.report())
        shutil.rmtree(self.repo / ".cache")
        gate, _ = self.hold("dropped-gate")
        result = self.run_all(TEST_SSH_SILENT_DROP="1", TEST_REMOTE_HOLD_FIFO=str(gate))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"went \d+ seconds without a heartbeat; stopping its run there\n")
        self.assertIn(f"Running on this Mac: the second Mac, {HOST}, stopped its run when this Mac's heartbeat "
                      "ended\n", result.stdout)
        self.assertEqual(self.owners()[-3:], [self.repo.resolve()] * 3)
        self.assertTrue(self.lane_free())


if __name__ == "__main__":
    unittest.main()
