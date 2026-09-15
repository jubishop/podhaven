"""Exercise the version command against disposable Xcode projects."""

import re
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from local_validation_fixture import install_gate


ROOT = Path(__file__).resolve().parents[2]


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven version ")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        (self.repo / "bin").mkdir()
        (self.repo / "PodHaven.xcodeproj").mkdir()
        self.command = self.repo / "bin/version"
        if (ROOT / "bin/version").exists():
            shutil.copy2(ROOT / "bin/version", self.command)
        self.project = self.repo / "PodHaven.xcodeproj/project.pbxproj"
        source = (ROOT / "PodHaven.xcodeproj/project.pbxproj").read_text()
        self.original = re.sub(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = 1.0;", source)
        self.project.write_text(self.original)
        self.env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        commands = Path(self.temp.name) / "commands"
        install_gate(self.repo, commands)
        self.env.update(PATH=str(commands) + os.pathsep + self.env["PATH"],
                        TEST_ALL_FIXTURE=self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Version Test")
        self.git("config", "user.email", "version@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial fixture")
        self.remote = self.repo / ".git/test-remote.git"
        self.git("init", "--bare", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("push", "-u", "origin", "main")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], env=self.env,
                                       stderr=subprocess.PIPE, text=True).strip()

    def run_version(self, *args, **env):
        return subprocess.run(
            ["python3", str(self.command), *args],
            cwd=self.temp.name,
            text=True,
            capture_output=True,
            env={**self.env, **env},
            check=False,
        )

    def test_failed_full_validation_leaves_version_local_and_retries_once(self):
        initial = self.git("rev-parse", "origin/main")
        for setting in ("TEST_BUILD_FAILURE", "TEST_SKIPPED", "TEST_MACRO_WARNING", "TEST_MISSING_BUNDLE"):
            with self.subTest(setting=setting):
                result = self.run_version("1.1", **{setting: "1"})
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.git("rev-parse", "origin/main"), initial)
                self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
                self.assertTrue((self.repo / ".git/podhaven-version-push").exists())
        result = self.run_version("1.1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))

    def test_unsupported_toolchain_stops_before_version_commit_or_push(self):
        result = self.run_version("1.1", TEST_XCODE_VERSION="26.5")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Xcode 27+", result.stderr)
        self.assertEqual(self.project.read_text(), self.original)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "1")

    def test_changes_only_app_version_in_every_configuration(self):
        result = self.run_version("1.0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.project.read_text(),
            self.original.replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = 1.0.1;"),
        )
        self.assertIn("1.0.1", result.stdout)
        self.assertEqual(self.git("log", "-1", "--format=%s"), "Change version number to 1.0.1")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))
        self.assertFalse(self.git("status", "--porcelain"))

    def test_dirty_worktree_prevents_setting_but_not_reading_version(self):
        (self.repo / "unrelated.txt").write_text("User work")
        for staged in (False, True):
            if staged:
                self.git("add", "unrelated.txt")
            result = self.run_version("1.1")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean working tree", result.stderr)
            self.assertEqual(self.project.read_text(), self.original)
            self.assertEqual(self.run_version().stdout.strip(), "1.0")

    def test_failed_push_retries_without_a_duplicate_commit(self):
        hook = self.remote / "hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.run_version("1.1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        hook.unlink()
        result = self.run_version("1.1", TEST_BUILD_FAILURE="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))

    def test_reports_version_without_changing_project(self):
        result = self.run_version()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1.0")
        self.assertEqual(self.project.read_text(), self.original)
        self.assertEqual(self.run_version("--help").returncode, 0)
        self.assertFalse((Path(self.temp.name) / "gate-events").exists())

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
