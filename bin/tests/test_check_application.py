"""Run bin/check-application in a disposable repository with stand-in tooling suites."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
SKILL_SUITE = ".agents/skills/example/scripts/test_example.py"


class CheckApplicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven check-application ")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name).resolve()
        (self.repo / "bin/tests").mkdir(parents=True)
        shutil.copy2(ROOT / "bin/check-application", self.repo / "bin/check-application")
        (self.repo / "bin/tests/test_probe.py").write_text(
            "import unittest\n\n\nclass ProbeTests(unittest.TestCase):\n    def test_runs(self):\n        pass\n")
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
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
                result = subprocess.run([str(self.repo / "bin/check-application")], cwd=self.repo, env=self.env,
                                        text=True, capture_output=True, timeout=120)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Tooling tests failed: " + SKILL_SUITE + "\n", result.stderr)


if __name__ == "__main__":
    unittest.main()
