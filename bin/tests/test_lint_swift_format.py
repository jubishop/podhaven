"""Run bin/lint-swift-format in a disposable repository against a stand-in swift-format.

The stand-in reproduces the output and exit status of swift-format 6.4.4: diagnostics go to standard
error, --strict exits 1 on any finding, a file it cannot parse gets untagged errors, and an unreadable
configuration gets a location-free error."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    "PodHaven/App.swift": "struct App {}\n",
    "PodHaven/Views/Card.swift": "struct Card {}\n\n// MARK: - Preview\n\n#Preview {}\n",
    "PodHavenIntents/Intent.swift": "struct Intent {}\n",
    "PodHavenMacros/Sources/Macro.swift": "struct Macro {}\n",
    "PodHavenShare/Share.swift": "struct Share {}\n",
    "PodHavenWidget/Widget.swift": "struct Widget {}\n",
}
FAKE_SWIFT_FORMAT = """\
import json, os, sys
from pathlib import Path
arguments = sys.argv[1:]
Path(os.environ["FAKE_ARGUMENTS"]).write_text(json.dumps(arguments))
try:
    json.loads(Path(arguments[arguments.index("--configuration") + 1]).read_text())
except ValueError:
    print("<unknown>: error: Unable to read configuration: The given data was not valid JSON.", file=sys.stderr)
    sys.exit(1)
sys.stderr.write(os.environ["FAKE_OUTPUT"].replace("{root}", os.getcwd()))
sys.exit(int(os.environ["FAKE_STATUS"]))
"""
PREVIEW_RULE = "{root}/PodHaven/Views/Card.swift:5:1: error: [NeverForceUnwrap] do not force unwrap 'x'\n"


class LintSwiftFormatTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven lint-swift-format ")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name).resolve()
        (self.repo / "bin").mkdir()
        shutil.copy2(ROOT / "bin/lint-swift-format", self.repo / "bin/lint-swift-format")
        shutil.copy2(ROOT / ".swift-format", self.repo / ".swift-format")
        for name, source in SOURCES.items():
            (self.repo / name).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / name).write_text(source)
        self.fake = self.repo / "fake-swift-format"
        self.fake.write_text(f"#!{sys.executable}\n{FAKE_SWIFT_FORMAT}")
        self.fake.chmod(0o755)
        self.arguments = self.repo / "fake-arguments.json"

    def lint(self, output="", status=0, swift_format=None):
        env = {**os.environ, "SWIFT_FORMAT": str(swift_format or self.fake), "FAKE_ARGUMENTS": str(self.arguments),
               "FAKE_OUTPUT": output, "FAKE_STATUS": str(status), "PYTHONDONTWRITEBYTECODE": "1"}
        return subprocess.run([sys.executable, str(self.repo / "bin/lint-swift-format")], cwd=self.repo,
                              capture_output=True, text=True, env=env, check=False)

    def assertFails(self, result, *expected):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("lint passed", result.stdout)
        for text in expected:
            self.assertIn(text, result.stderr)

    def test_lints_every_production_target(self):
        result = self.lint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"swift-format lint passed ({len(SOURCES)} production files)", result.stdout)
        linted = {Path(argument).relative_to(self.repo).as_posix()
                  for argument in json.loads(self.arguments.read_text()) if argument.endswith(".swift")}
        self.assertEqual(linted, set(SOURCES))

    def test_parse_failure_fails_with_swift_format_output(self):
        for name in ("PodHaven/App.swift", "PodHaven/Views/Card.swift"):
            with self.subTest(name):
                error = f"{name}:5:10: error: expected ')' to end parameter clause"
                self.assertFails(self.lint(f"{{root}}/{error}\n", status=1), error)

    def test_failing_binary_fails(self):
        self.assertFails(self.lint(swift_format="/usr/bin/false"), "exited with status 1")

    def test_missing_binary_fails_without_a_traceback(self):
        result = self.lint(swift_format=self.repo / "missing-swift-format")
        self.assertFails(result, "missing-swift-format")
        self.assertNotIn("Traceback", result.stderr)

    def test_invalid_configuration_fails_with_swift_format_output(self):
        (self.repo / ".swift-format").write_text("{ not json\n")
        self.assertFails(self.lint(), "<unknown>: error: Unable to read configuration")

    def test_untagged_warning_fails_even_when_swift_format_succeeds(self):
        warning = "PodHavenWidget/Widget.swift:1:1: warning: unexpected condition"
        self.assertFails(self.lint(f"{{root}}/{warning}\n"), warning)

    def test_rule_findings_fail_only_outside_preview_regions(self):
        result = self.lint(PREVIEW_RULE, status=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lint passed", result.stdout)
        finding = "PodHavenShare/Share.swift:1:1: error: [Indentation] unindent by 2 spaces"
        self.assertFails(self.lint(PREVIEW_RULE + f"{{root}}/{finding}\n", status=1), finding, "1 issue(s)")

    def test_other_output_fails_a_nonzero_exit_despite_preview_findings(self):
        self.assertFails(self.lint(PREVIEW_RULE + "Stack dump:\n", status=1), "Stack dump:", "exited with status 1")


if __name__ == "__main__":
    unittest.main()
