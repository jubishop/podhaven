"""Exercise the machine-wide validation slots directly and through bin/with-my-mac-lock."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import unittest

import fake_caffeinate
import hang_guard
import service_guard


BIN = Path(__file__).resolve().parents[1]
# Holds a slot as HOLDER, then runs COMMAND the way managed bin/check starts bin/check-application, without passing
# it any descriptor, or without a command waits for a line on standard input.
DRIVER = r'''
import subprocess, sys
sys.path.insert(0, sys.argv[1])
from _validation_slot import validation_slot
with validation_slot(sys.argv[2]):
    print("held " + sys.argv[2], flush=True)
    if sys.argv[3:]:
        sys.exit(subprocess.run(sys.argv[3:]).returncode)
    sys.stdin.readline()
'''


def driver(holder, *command):
    return [sys.executable, "-B", "-c", DRIVER, str(BIN), holder, *command]


def queued(ahead):
    if not ahead:
        return "Next in line for a validation slot\n"
    return f"Queued behind {ahead} earlier waiting run{'s' if ahead > 1 else ''}\n"


class ValidationSlotTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven validation slot ")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.slots = self.home / ".cache/podhaven"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("PODHAVEN_")}
        self.env["HOME"] = str(self.home)
        commands = self.home / "commands"
        commands.mkdir()
        fake_caffeinate.install(commands)
        self.env["PATH"] = str(commands) + os.pathsep + self.env["PATH"]

    def start(self, command, **env):
        process = hang_guard.start(command, env={**self.env, **env}, cwd=self.home, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(hang_guard.HANG_LIMIT, hang_guard.kill, (process,))
        watchdog.start()
        self.addCleanup(watchdog.cancel)
        self.addCleanup(hang_guard.stop, process)
        return process

    def hold(self, holder, **env):
        process = self.start(driver(holder), **env)
        self.assertEqual(process.stdout.readline(), f"held {holder}\n")
        return process

    def release(self, process):
        process.stdin.close()
        self.assertEqual(hang_guard.wait(process), 0)

    def assert_waiting(self, process, count, *holders, ahead=0):
        """Read a waiting run's report of each slot's holder, as a process ID and command or None for a free slot."""
        self.assertEqual(process.stderr.readline(),
                         f"Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS={count}), held by:\n")
        for number, holder in enumerate(holders, 1):
            if holder is None:
                self.assertEqual(process.stderr.readline(), f"  slot {number}: free\n")
            else:
                self.assertRegex(process.stderr.readline(),
                                 rf"^  slot {number}: pid {holder[0]} since .+: {holder[1]}\n$")
        if ahead:
            self.assertEqual(process.stderr.readline(), queued(ahead))

    def assert_changed(self, process, holder, ahead):
        self.assertRegex(process.stderr.readline(),
                         rf"^Validation slot 1 is now held by pid {holder[0]} since .+: {holder[1]}\n$")
        self.assertEqual(process.stderr.readline(), queued(ahead))

    def queue(self):
        return sorted((self.slots / "validation-queue").iterdir())

    def test_a_run_waits_while_every_slot_is_held_and_names_the_holders(self):
        first = self.hold("first")
        second = self.hold("second")
        third = self.start(driver("third"))
        self.assert_waiting(third, 2, (first.pid, "first"), (second.pid, "second"))
        self.release(second)
        self.assertEqual(third.stderr.readline(), "Took validation slot 2\n")
        self.assertEqual(third.stdout.readline(), "held third\n")
        self.assertRegex((self.slots / "validation-slot-2.lock").read_text(), rf"^pid {third.pid} since .+: third\n$")
        self.release(third)
        self.release(first)
        for number in (1, 2):
            self.assertEqual((self.slots / f"validation-slot-{number}.lock").read_text(), "")

    def test_a_killed_holder_releases_its_slot(self):
        holder = self.hold("holder", PODHAVEN_VALIDATION_SLOTS="1")
        waiter = self.start(driver("waiter", "/bin/echo", "ran"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assert_waiting(waiter, 1, (holder.pid, "holder"))
        os.kill(holder.pid, signal.SIGKILL)
        self.assertEqual(hang_guard.wait(holder), -signal.SIGKILL)
        self.assertEqual(waiter.stderr.readline(), "Took validation slot 1\n")
        self.assertEqual(waiter.stdout.read(), "held waiter\nran\n")
        self.assertEqual(hang_guard.wait(waiter), 0)

    def test_waiting_runs_take_the_slot_in_the_order_they_began_waiting(self):
        holder = self.hold("holder", PODHAVEN_VALIDATION_SLOTS="1")
        waiters = []
        for ahead, name in enumerate(("first", "second", "third")):
            waiters.append(self.start(driver(name), PODHAVEN_VALIDATION_SLOTS="1"))
            self.assert_waiting(waiters[-1], 1, (holder.pid, "holder"), ahead=ahead)
        # Stopping the oldest waiter leaves the freed slot free past every later run's poll, as a slow poll can.
        os.kill(waiters[0].pid, signal.SIGSTOP)
        self.release(holder)
        last = self.start(driver("fourth", "/bin/echo", "ran"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assert_waiting(last, 1, None, ahead=3)
        os.kill(waiters[0].pid, signal.SIGCONT)
        waiters.append(last)
        for index, name in enumerate(("first", "second", "third")):
            taker = waiters[index]
            self.assertEqual(taker.stderr.readline(), "Took validation slot 1\n")
            self.assertEqual(taker.stdout.readline(), f"held {name}\n")
            for ahead, waiter in enumerate(waiters[index + 1:]):
                self.assert_changed(waiter, (taker.pid, name), ahead)
            self.release(taker)
        self.assertEqual(last.stderr.read(), "Took validation slot 1\n")
        self.assertEqual(last.stdout.read(), "held fourth\nran\n")
        self.assertEqual(hang_guard.wait(last), 0)
        self.assertEqual(self.queue(), [])

    def test_a_waiting_run_that_is_killed_leaves_the_queue(self):
        holder = self.hold("holder", PODHAVEN_VALIDATION_SLOTS="1")
        first = self.start(driver("first"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assert_waiting(first, 1, (holder.pid, "holder"))
        second = self.start(driver("second", "/bin/echo", "ran"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assert_waiting(second, 1, (holder.pid, "holder"), ahead=1)
        self.assertEqual(len(self.queue()), 2)
        os.kill(first.pid, signal.SIGKILL)
        self.assertEqual(hang_guard.wait(first), -signal.SIGKILL)
        self.assertEqual(second.stderr.readline(), queued(0))
        self.assertEqual(len(self.queue()), 1)
        self.release(holder)
        self.assertEqual(second.stderr.read(), "Took validation slot 1\n")
        self.assertEqual(second.stdout.read(), "held second\nran\n")
        self.assertEqual(hang_guard.wait(second), 0)
        self.assertEqual(self.queue(), [])

    def test_a_nested_run_reuses_its_slot_ahead_of_waiting_runs(self):
        # The nested run starts after another run queues for the only slot, which its own outer run holds.
        outer = self.start(driver("outer", "/bin/sh", "-c", 'read line && exec "$@"', "sh",
                                  *driver("inner", "/bin/echo", "nested")), PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(outer.stdout.readline(), "held outer\n")
        waiter = self.start(driver("waiter", "/bin/echo", "ran"), PODHAVEN_VALIDATION_SLOTS="1")
        self.assert_waiting(waiter, 1, (outer.pid, "outer"))
        outer.stdin.write("go\n")
        outer.stdin.close()
        self.assertEqual(outer.stdout.read(), "held inner\nnested\n")
        self.assertEqual(outer.stderr.read(), "")
        self.assertEqual(hang_guard.wait(outer), 0)
        self.assertEqual(waiter.stderr.read(), "Took validation slot 1\n")
        self.assertEqual(waiter.stdout.read(), "held waiter\nran\n")
        self.assertEqual(hang_guard.wait(waiter), 0)

    def test_nested_runs_reuse_the_slot_without_inheriting_its_descriptor(self):
        # With one slot, a nested run that waited for another would wait on its own holder forever.
        result = hang_guard.run(driver("outer", *driver("inner", *driver("innermost", "/bin/echo", "nested"))),
                                env={**self.env, "PODHAVEN_VALIDATION_SLOTS": "1"}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "held outer\nheld inner\nheld innermost\nnested\n")
        self.assertEqual(result.stderr, "")

    def test_a_slot_is_reused_only_under_its_live_holder(self):
        slot = self.slots / "validation-slot-1.lock"
        holder = self.hold("holder", PODHAVEN_VALIDATION_SLOTS="1")
        other_home = self.home / "other/.cache/podhaven/validation-slot-1.lock"
        for case, claim in (("another process", f"{os.getpid()}:{slot}"),
                            ("another home", f"{holder.pid}:{other_home}"),
                            ("no process", f"x:{slot}")):
            with self.subTest(case):
                waiter = self.start(driver("waiter"), PODHAVEN_VALIDATION_SLOTS="1", PODHAVEN_VALIDATION_SLOT=claim)
                self.assert_waiting(waiter, 1, (holder.pid, "holder"))
                hang_guard.stop(waiter)
        record = slot.read_text()
        self.release(holder)
        # The released slot keeps no record, but even a leftover one names no live holder.
        slot.write_text(record)
        result = hang_guard.run(driver("free", "/bin/cat", str(slot)), text=True, capture_output=True,
                                env={**self.env, "PODHAVEN_VALIDATION_SLOTS": "1",
                                     "PODHAVEN_VALIDATION_SLOT": f"{holder.pid}:{slot}"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertRegex(result.stdout, r"^held free\npid \d+ since .+: free\n$")
        self.assertNotIn(f"pid {holder.pid} ", result.stdout)

    def test_a_focused_run_takes_its_slot_before_the_my_mac_lock(self):
        lock = BIN / "with-my-mac-lock"
        first = self.start([sys.executable, "-B", str(lock), "/bin/sh", "-c", "echo held; read line; true"])
        self.assertEqual(first.stdout.readline(), "held\n")
        second = self.start([sys.executable, "-B", str(lock), "/bin/echo", "second"])
        self.assertIn("Waiting for the My Mac test lock", second.stderr.readline())
        # The second run holds its slot while it waits for the My Mac lock.
        self.assertRegex((self.slots / "validation-slot-2.lock").read_text(),
                         rf"^pid {second.pid} since .+: /bin/echo second in ")
        third = self.start([sys.executable, "-B", str(lock), "/bin/echo", "third"])
        self.assert_waiting(third, 2, (first.pid, "/bin/sh -c 'echo held; read line; true' in .+"),
                            (second.pid, "/bin/echo second in .+"))
        self.release(first)
        self.assertEqual(second.stdout.read(), "second\n")
        self.assertEqual(hang_guard.wait(second), 0)
        self.assertEqual(third.stdout.read(), "third\n")
        self.assertEqual(hang_guard.wait(third), 0)
        self.assertIn("Took validation slot", third.stderr.read())

    def test_invalid_slot_counts_fail_clearly(self):
        for value in ("0", "-1", "two", "1.5", " 2", ""):
            with self.subTest(value=value):
                result = hang_guard.run([sys.executable, "-B", str(BIN / "with-my-mac-lock"), "/bin/echo", "ran"],
                                        env={**self.env, "PODHAVEN_VALIDATION_SLOTS": value}, text=True,
                                        capture_output=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "with-my-mac-lock: PODHAVEN_VALIDATION_SLOTS must be a positive "
                                                f"integer, not {value!r}\n")
        self.assertFalse(self.slots.exists())


if __name__ == "__main__":
    unittest.main()
