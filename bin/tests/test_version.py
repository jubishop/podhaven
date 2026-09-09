"""Exercise the version command against disposable Xcode projects."""

import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven version ")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / "bin").mkdir()
        (self.repo / "PodHaven.xcodeproj").mkdir()
        self.command = self.repo / "bin/version"
        if (ROOT / "bin/version").exists():
            shutil.copy2(ROOT / "bin/version", self.command)
        self.project = self.repo / "PodHaven.xcodeproj/project.pbxproj"
        source = (ROOT / "PodHaven.xcodeproj/project.pbxproj").read_text()
        self.original = re.sub(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = 1.0;", source)
        self.project.write_text(self.original)

    def run_version(self, *args):
        return subprocess.run(
            ["python3", str(self.command), *args],
            cwd=self.temp.name,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_changes_only_app_version_in_every_configuration(self):
        result = self.run_version("1.0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.project.read_text(),
            self.original.replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = 1.0.1;"),
        )
        self.assertIn("1.0.1", result.stdout)

    def test_reports_version_without_changing_project(self):
        result = self.run_version()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1.0")
        self.assertEqual(self.project.read_text(), self.original)

    def test_rejects_invalid_or_older_versions_without_writing(self):
        for version in ("0.9", "1.0-beta", "1.0.1.2", "1.01", "", "1.0; OTHER = YES"):
            with self.subTest(version=version):
                result = self.run_version(version)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.project.read_text(), self.original)

    def test_accepts_numeric_increase_and_same_version(self):
        for version in ("1.0", "1.9", "1.10", "2.0"):
            with self.subTest(version=version):
                result = self.run_version(version)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.run_version().stdout.strip(), version)

    def test_rejects_missing_or_inconsistent_settings(self):
        for source in (
            self.original.replace("MARKETING_VERSION", "UNRELATED_SETTING"),
            self.original.replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = 2.0;", 1),
        ):
            with self.subTest(source=source[:80]):
                self.project.write_text(source)
                result = self.run_version("1.0.1")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("error:", result.stderr)
                self.assertEqual(self.project.read_text(), source)


if __name__ == "__main__":
    unittest.main()
