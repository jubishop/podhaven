"""Keep every tooling test from running a real command for a live external service."""

import ast
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
TESTS = Path(__file__).resolve().parent
LIVE_COMMANDS = ("claude", "curl", "fastlane", "gh", "llm", "sentry", "sentry-cli", "xcodebuild", "xcrun")
SUITE = r'''
import os
import subprocess
import tempfile
import unittest

import service_guard


class ForgottenFakeTests(unittest.TestCase):
    pass


for name in os.environ["LIVE_COMMANDS"].split():
    def test(self, name=name):
        with tempfile.TemporaryDirectory() as fakes:
            subprocess.run(["/bin/sh", "-c", name + " --version >/dev/null 2>&1 || true"],
                           env={**os.environ, "PATH": fakes + os.pathsep + os.environ["PATH"]})
    setattr(ForgottenFakeTests, "test_" + name.replace("-", "_"), test)
'''


class ServiceGuardTests(unittest.TestCase):
    def test_every_tooling_suite_imports_the_guard(self):
        suites = [*TESTS.glob("test_*.py"), *(ROOT / ".agents").rglob("test_*.py")]
        unguarded = sorted(str(path.relative_to(ROOT)) for path in suites
                           if not any(isinstance(node, ast.Import)
                                      and any(alias.name == "service_guard" for alias in node.names)
                                      for node in ast.parse(path.read_text()).body))
        self.assertIn(ROOT / ".agents/scripts/sentry-cli/test_sentry_helpers.py", suites)
        self.assertEqual(unguarded, [])

    def test_a_forgotten_fake_fails_its_test_without_running_the_real_command(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            real = base / "real"
            real.mkdir()
            reached = base / "reached"
            for name in LIVE_COMMANDS:
                (real / name).write_text(f"#!/bin/sh\necho {name} >> {shlex.quote(str(reached))}\n")
                (real / name).chmod(0o755)
            (base / "test_forgotten_fake.py").write_text(SUITE)
            result = subprocess.run([sys.executable, "-B", "-m", "unittest", "-v", "test_forgotten_fake"],
                                    cwd=base, text=True, capture_output=True, timeout=30,
                                    env={**os.environ, "PATH": str(real) + os.pathsep + os.environ["PATH"],
                                         "PYTHONPATH": str(TESTS), "LIVE_COMMANDS": " ".join(LIVE_COMMANDS)})
            self.assertFalse(reached.exists(), reached.read_text() if reached.exists() else "")
            self.assertIn(f"Ran {len(LIVE_COMMANDS)} tests", result.stderr)
            self.assertIn(f"FAILED (failures={len(LIVE_COMMANDS)})", result.stderr)
            for name in LIVE_COMMANDS:
                self.assertIn(f"\n{name} --version\n", result.stderr)


if __name__ == "__main__":
    unittest.main()
