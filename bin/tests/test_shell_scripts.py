from pathlib import Path
import subprocess
import unittest


TESTS = Path(__file__).resolve().parent


class ShellScriptTests(unittest.TestCase):
    def test_shell_scripts_pass(self):
        scripts = sorted(TESTS.glob("*.sh"))
        self.assertTrue(scripts)
        for script in scripts:
            with self.subTest(script=script.name):
                result = subprocess.run(["/bin/bash", str(script)], text=True, capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
