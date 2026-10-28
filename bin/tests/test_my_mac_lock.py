"""Exercise the machine-wide My Mac test lock through bin/with-my-mac-lock."""

import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import unittest

import service_guard


COMMAND = Path(__file__).resolve().parents[1] / "with-my-mac-lock"
PROBE = r'''
import fcntl, os, pathlib, sys
lock = pathlib.Path.home() / ".cache/podhaven/my-mac-tests.lock"
print(lock.read_text().strip())
print(os.getpid())
with lock.open("a") as probe:
    try:
        fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
        print("free")
    except BlockingIOError:
        print("held")
sys.exit(3)
'''


class MyMacLockTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven my mac lock ")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.lock = self.home / ".cache/podhaven/my-mac-tests.lock"
        self.env = {**os.environ, "HOME": str(self.home)}
        self.env.pop("PODHAVEN_MY_MAC_LOCK_FD", None)

    def run_locked(self, *command):
        return subprocess.run([sys.executable, "-B", str(COMMAND), *command],
                              env=self.env, text=True, capture_output=True, timeout=30)

    def start(self, *command):
        process = subprocess.Popen([sys.executable, "-B", str(COMMAND), *command], env=self.env, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(30, process.kill)
        watchdog.start()
        self.addCleanup(self.stop, process, watchdog)
        return process

    def stop(self, process, watchdog):
        watchdog.cancel()
        if process.poll() is None:
            process.kill()
        process.wait()
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close()

    def hold(self):
        holder = self.start("/bin/sh", "-c", 'echo held; read line; echo released > "$HOME/released"')
        self.assertEqual(holder.stdout.readline(), "held\n")
        return holder

    def assert_free(self):
        with self.lock.open("a") as probe:
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_command_runs_holding_the_lock_and_releases_it_on_exit(self):
        probe = self.home / "probe.py"
        probe.write_text(PROBE)
        result = self.run_locked(sys.executable, str(probe))
        self.assertEqual(result.returncode, 3, result.stderr)
        holder, pid, state = result.stdout.splitlines()
        self.assertEqual(state, "held")
        self.assertTrue(holder.startswith(f"pid {pid} since "), holder)
        self.assertIn(str(probe), holder)
        self.assertEqual(result.stderr, "")
        self.assert_free()

    def test_second_run_waits_until_the_holder_exits(self):
        holder = self.hold()
        waiter = self.start("/bin/cat", str(self.home / "released"))
        waiting = waiter.stderr.readline()
        self.assertIn("Waiting for the My Mac test lock", waiting)
        self.assertIn(f"pid {holder.pid} since ", waiting)
        self.assertIn("echo held", waiting)
        holder.stdin.close()
        self.assertEqual(holder.wait(timeout=30), 0)
        self.assertEqual(waiter.stdout.read(), "released\n")
        self.assertEqual(waiter.wait(timeout=30), 0)
        self.assert_free()

    def test_killed_holder_releases_the_lock(self):
        holder = self.hold()
        waiter = self.start("/bin/echo", "ran")
        self.assertIn("Waiting for the My Mac test lock", waiter.stderr.readline())
        os.kill(holder.pid, signal.SIGKILL)
        self.assertEqual(holder.wait(timeout=30), -signal.SIGKILL)
        self.assertEqual(waiter.stdout.read(), "ran\n")
        self.assertEqual(waiter.wait(timeout=30), 0)
        self.assert_free()

    def test_nested_runs_reuse_the_inherited_lock(self):
        result = self.run_locked(sys.executable, "-B", str(COMMAND), "/bin/echo", "nested")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "nested\n")
        self.assertEqual(result.stderr, "")
        self.assert_free()

    def test_missing_command_fails_and_releases_the_lock(self):
        for command, status, message in (((), 2, "usage"), (("/nonexistent/command",), 127, "/nonexistent/command")):
            with self.subTest(command=command):
                result = self.run_locked(*command)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertIn(message, result.stderr.lower())
        self.assert_free()


if __name__ == "__main__":
    unittest.main()
