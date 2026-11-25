"""Run bin/check-application in a disposable repository with stand-in tooling suites."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

import hang_guard
import service_guard
from test_validation_slot import DRIVER


ROOT = Path(__file__).resolve().parents[2]
SKILL_SUITE = ".agents/skills/example/scripts/test_example.py"


class CheckApplicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven check-application ")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name).resolve()
        (self.repo / "bin/tests").mkdir(parents=True)
        for name in ("check-application", "_validation_slot.py"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        (self.repo / "bin/tests/test_probe.py").write_text(
            "import unittest\n\n\nclass ProbeTests(unittest.TestCase):\n    def test_runs(self):\n        pass\n")
        self.env = {key: value for key, value in os.environ.items() if not key.startswith(("GIT_", "PODHAVEN_"))}
        self.env.update(HOME=str(self.repo / "home"), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        PYTHONDONTWRITEBYTECODE="1")
        subprocess.run(["git", "init", "--quiet"], cwd=self.repo, env=self.env, check=True)

    def test_a_skill_suite_fails_unless_it_runs_tests(self):
        suites = {
            # Run as a script, this suite would exit cleanly without running its failing test.
            "without a main block": "import unittest\n\n\nclass ExampleTests(unittest.TestCase):\n"
                                    "    def test_answer(self):\n        self.fail('the suite ran')\n",
            "without tests": "import unittest\n\nif __name__ == '__main__':\n    unittest.main()\n",
        }
        for case, source in suites.items():
            with self.subTest(case):
                suite = self.repo / SKILL_SUITE
                suite.parent.mkdir(parents=True, exist_ok=True)
                suite.write_text(source)
                result = hang_guard.run([str(self.repo / "bin/check-application")], cwd=self.repo, env=self.env,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Tooling checks failed: " + SKILL_SUITE + "\n", result.stderr)

    def run_checks(self, **env):
        return hang_guard.run([sys.executable, str(self.repo / "bin/check-application")], cwd=self.repo,
                              env={**self.env, **env}, text=True, capture_output=True)

    def test_scripts_and_workflows_outside_foundation_checks_are_linted(self):
        cases = {
            "ShellCheck": (".agents/scripts/example/run.sh",
                           '#!/bin/bash\n# shellcheck source=lib.sh\nsource "$(dirname "$0")/lib.sh"\necho "$name"\n',
                           "#!/bin/bash\nif true; then\n"),
            "actionlint": (".github/workflows/example.yml",
                           "on: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
                           "on: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n"),
            "fish syntax bin/example": ("bin/example", "#!/usr/bin/env fish\nif true\n    echo ok\nend\n",
                                        "#!/usr/bin/env fish\nif true\n"),
            "Ruby syntax fastlane/Fastfile": ("fastlane/Fastfile", "lane :example do\nend\n", "lane :example do\n"),
        }
        (self.repo / ".agents/scripts/example").mkdir(parents=True)
        (self.repo / ".agents/scripts/example/lib.sh").write_text("#!/bin/bash\nexport name=example\n")
        for path, valid, _ in cases.values():
            (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / path).write_text(valid)
        result = self.run_checks()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for label, (path, valid, broken) in cases.items():
            with self.subTest(label):
                self.assertIn("Running " + label + "\n", result.stdout)
                (self.repo / path).write_text(broken)
                try:
                    failed = self.run_checks()
                finally:
                    (self.repo / path).write_text(valid)
                self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
                self.assertIn("Tooling checks failed: " + label + "\n", failed.stderr)
                self.assertIn("Running bin/tests\n", failed.stdout)

    def start(self, command, **env):
        process = hang_guard.start(command, cwd=self.repo, env={**self.env, **env}, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(hang_guard.HANG_LIMIT, hang_guard.kill, (process,))
        watchdog.start()
        self.addCleanup(watchdog.cancel)
        self.addCleanup(hang_guard.stop, process)
        return process

    def test_the_checks_hold_a_validation_slot_unless_they_run_inside_its_holder(self):
        (self.repo / "bin/tests/test_slot_record.py").write_text(
            "import pathlib, unittest\n\n\nclass SlotRecordTests(unittest.TestCase):\n"
            "    def test_prints_the_slot_record(self):\n"
            "        print((pathlib.Path.home() / '.cache/podhaven/validation-slot-1.lock').read_text(), end='')\n")
        application = (sys.executable, str(self.repo / "bin/check-application"))
        holder = [sys.executable, "-B", "-c", DRIVER, str(self.repo / "bin"), "holder"]
        # Managed bin/check starts bin/check-application without passing it the slot's descriptor.
        result = hang_guard.run([*holder, *application], cwd=self.repo, text=True, capture_output=True,
                                env={**self.env, "PODHAVEN_VALIDATION_SLOTS": "1"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Waiting", result.stderr)
        self.assertRegex(result.stdout, r"\npid \d+ since .+: holder\n")
        held = self.start(holder, PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(held.stdout.readline(), "held holder\n")
        checks = self.start(application, PODHAVEN_VALIDATION_SLOTS="1")
        self.assertEqual(checks.stderr.readline(),
                         "Waiting for a validation slot (PODHAVEN_VALIDATION_SLOTS=1), held by:\n")
        self.assertRegex(checks.stderr.readline(), rf"^  slot 1: pid {held.pid} since .+: holder\n$")
        held.stdin.close()
        self.assertEqual(hang_guard.wait(held), 0)
        output, errors = hang_guard.finish(checks)
        self.assertEqual(checks.returncode, 0, output + errors)
        self.assertIn("Took validation slot 1\n", errors)
        self.assertIn(f"\npid {checks.pid} since ", output)
        self.assertIn(f": bin/check-application in {self.repo}\n", output)

    def test_an_invalid_validation_slot_count_fails_clearly(self):
        result = self.run_checks(PODHAVEN_VALIDATION_SLOTS="0")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "bin/check-application: PODHAVEN_VALIDATION_SLOTS must be a positive integer, "
                                        "not '0'\n")
        self.assertNotIn("Running", result.stdout)

    def test_a_missing_linter_fails_its_check_clearly(self):
        (self.repo / ".github/workflows").mkdir(parents=True)
        (self.repo / ".github/workflows/example.yml").write_text(
            "on: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n")
        temporary = tempfile.TemporaryDirectory(prefix="podhaven check-application commands ")
        self.addCleanup(temporary.cleanup)
        commands = Path(temporary.name)
        (commands / "git").symlink_to(shutil.which("git"))
        result = self.run_checks(PATH=str(commands))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("actionlint is required for bin/check --full", result.stderr)
        self.assertIn("Tooling checks failed: actionlint\n", result.stderr)


if __name__ == "__main__":
    unittest.main()
