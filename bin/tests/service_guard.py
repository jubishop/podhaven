"""Keep tooling tests from running real commands for live external services.

Importing this module puts failing stand-ins for those commands ahead of PATH, so a
suite that forgets a fake cannot act on real accounts. Each test that runs a stand-in
fails, even when the script under test ignores the command's failure."""

import atexit
import os
from pathlib import Path
import shlex
import shutil
import tempfile
import unittest


COMMANDS = ("claude", "curl", "fastlane", "gh", "llm", "sentry", "sentry-cli", "xcodebuild", "xcrun")
GUARD = Path(tempfile.mkdtemp(prefix="podhaven-service-guard-"))
atexit.register(shutil.rmtree, GUARD, True)
BLOCKED = GUARD / "blocked"
STUBS = GUARD / "bin"
STUBS.mkdir()
for name in COMMANDS:
    stub = STUBS / name
    stub.write_text(f"#!/bin/sh\nprintf '%s\\n' \"{name} $*\" >> {shlex.quote(str(BLOCKED))}\n"
                    f"echo 'service_guard: blocked the real {name}; fake it in this test.' >&2\nexit 1\n")
    stub.chmod(0o755)
os.environ["PATH"] = str(STUBS) + os.pathsep + os.environ.get("PATH", os.defpath)


def take_blocked():
    calls = BLOCKED.read_text().splitlines() if BLOCKED.exists() else []
    BLOCKED.unlink(missing_ok=True)
    return calls


def fail_if_blocked(test):
    if calls := take_blocked():
        test.fail("Fake every live-service command this test runs. Blocked:\n" + "\n".join(calls))


run_test = unittest.TestCase.run


def run_guarded(self, result=None):
    self.addCleanup(fail_if_blocked, self)
    return run_test(self, result)


unittest.TestCase.run = run_guarded
