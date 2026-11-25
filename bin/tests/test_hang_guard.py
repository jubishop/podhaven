"""Stop a hung command and everything it started before the test cleans up its files."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import hang_guard
import service_guard


# Reports ready, then keeps adding files to the folder for a bounded time even if its parent is killed.
WRITER = r'''
import os, sys, time
folder = sys.argv[1]
with open(os.path.join(folder, "writer"), "w") as stream:
    stream.write(str(os.getpid()))
print("ready", flush=True)
for index in range(3000):
    open(os.path.join(folder, f"{index}.txt"), "w").close()
    time.sleep(0.01)
'''
WAITS = "import subprocess, sys; subprocess.run([sys.executable, '-c', sys.argv[1], sys.argv[2]])"
LEAVES = "import subprocess, sys; subprocess.Popen([sys.executable, '-c', sys.argv[1], sys.argv[2]])"


class HangGuardTests(unittest.TestCase):
    def start_writer(self, parent):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven hang guard ")
        self.addCleanup(temporary.cleanup)
        folder = Path(temporary.name)
        process = hang_guard.start([sys.executable, "-c", parent, WRITER, str(folder)],
                                   stdout=subprocess.PIPE, text=True)
        self.addCleanup(hang_guard.stop, process)
        self.assertEqual(process.stdout.readline(), "ready\n")
        return process, temporary

    def assert_writer_ended_before_cleanup(self, temporary):
        folder = Path(temporary.name)
        with self.assertRaises(ProcessLookupError):
            os.kill(int((folder / "writer").read_text()), 0)
        temporary.cleanup()
        self.assertFalse(folder.exists())

    def test_a_timeout_ends_every_process_the_command_started_before_cleanup(self):
        process, temporary = self.start_writer(WAITS)
        with self.assertRaises(subprocess.TimeoutExpired):
            hang_guard.finish(process, timeout=0.1)
        self.assert_writer_ended_before_cleanup(temporary)

    def test_stopping_an_ended_command_ends_what_it_left_running(self):
        process, temporary = self.start_writer(LEAVES)
        self.assertEqual(hang_guard.wait(process), 0)
        hang_guard.stop(process)
        self.assert_writer_ended_before_cleanup(temporary)


if __name__ == "__main__":
    unittest.main()
