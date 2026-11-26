from pathlib import Path
import unittest

import hang_guard
import service_guard


TESTS = Path(__file__).resolve().parent


class ShellScriptTests(unittest.TestCase):
    def test_shell_scripts_pass(self):
        scripts = sorted(TESTS.glob("*.sh"))
        self.assertTrue(scripts)
        for script in scripts:
            with self.subTest(script=script.name):
                result = hang_guard.run(["/bin/bash", str(script)], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
