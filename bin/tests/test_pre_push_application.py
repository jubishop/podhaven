"""Push through the managed pre-push hook into a disposable remote and check bin/pre-push-application."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
# Stands in for the tooling tests: it records where it ran and fails while its checkout holds bin/broken.
APPLICATION = f"""#!{sys.executable}
import os, pathlib, sys
with open(os.environ["CHECK_CALLS"], "a") as calls:
    calls.write(os.getcwd() + "\\n")
sys.exit(1 if pathlib.Path("bin/broken").exists() else 0)
"""


class PrePushApplicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="podhaven pre-push ")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.repo = self.base / "checkout"
        self.remote = self.base / "remote.git"
        self.calls = self.base / "check calls"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(HOME=str(self.base / "home"), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.com",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.com",
                        CHECK_CALLS=str(self.calls), PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "--quiet", "--bare", "--initial-branch=main", str(self.remote), cwd=self.base)
        (self.repo / "bin/hooks").mkdir(parents=True)
        self.git("init", "--quiet", "--initial-branch=main")
        for name in ("hooks/pre-push", "knowledge-hook", "_knowledge.py", "check", "_checks.py",
                     "pre-push-application"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        (self.repo / "bin/check-application").write_text(APPLICATION)
        (self.repo / "bin/check-application").chmod(0o755)
        (self.repo / ".config").mkdir()
        shutil.copy2(ROOT / ".config/knowledge.json", self.repo / ".config/knowledge.json")
        for area in ("docs", "memory"):
            (self.repo / area).mkdir()
            (self.repo / area / "README.md").write_text("# Index\n")
        (self.repo / ".gitignore").write_text(".cache/\n")
        self.git("config", "core.hooksPath", "bin/hooks")
        self.git("remote", "add", "origin", str(self.remote))
        self.commit("Add the tooling")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env, text=True,
                              capture_output=True, check=True).stdout.strip()

    def commit(self, message):
        self.git("add", "--all")
        self.git("commit", "--quiet", "--message", message)
        return self.git("rev-parse", "HEAD")

    def push(self, *refs):
        return subprocess.run(["git", "push", "origin", *refs], cwd=self.repo, env=self.env, text=True,
                              capture_output=True, timeout=120)

    def remote_head(self, branch="main"):
        return self.git("rev-parse", "--verify", "--quiet", "refs/heads/" + branch, cwd=self.remote)

    def check_calls(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_refuses_a_push_until_the_pushed_tooling_passes_its_checks(self):
        accepted = self.git("rev-parse", "HEAD")
        self.assertEqual(self.push("main").returncode, 0)
        self.assertEqual(self.remote_head(), accepted)
        self.assertEqual(len(self.check_calls()), 1)
        (self.repo / "bin/broken").write_text("")
        self.commit("Break the tooling")
        # An uncommitted repair doesn't hide the failure of the revision being pushed.
        (self.repo / "bin/broken").unlink()
        result = self.push("main")
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertIn("bin/check --full failed", result.stderr)
        self.assertEqual(self.remote_head(), accepted)
        repaired = self.commit("Repair the tooling")
        result = self.push("main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head(), repaired)
        calls = self.check_calls()
        # The repair restores the first pushed tree, so the hook reuses that tree's pass.
        self.assertEqual(len(calls), 2)
        # Each check ran in a disposable checkout that the hook removed afterward.
        for call in calls:
            self.assertFalse(Path(call).exists(), call)
        self.assertEqual(self.git("worktree", "list", "--porcelain").count("worktree "), 1)

    def test_skips_pushes_that_change_only_application_code_or_pages(self):
        self.assertEqual(self.push("main").returncode, 0)
        (self.repo / "PodHaven").mkdir()
        (self.repo / "PodHaven/App.swift").write_text("struct App {}\n")
        (self.repo / "README.md").write_text("# Notes\n\nApplication notes.\n")
        self.commit("Change the application and a page")
        result = self.push("main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.check_calls()), 1)
        # A new branch adds no commits that the remote lacks.
        self.git("branch", "feature")
        self.assertEqual(self.push("feature").returncode, 0)
        self.assertEqual(len(self.check_calls()), 1)
        # Tooling tests read skill prose, so pages under bin/ and .agents/ count as tooling.
        self.git("checkout", "--quiet", "feature")
        (self.repo / ".agents/skills/example").mkdir(parents=True)
        (self.repo / ".agents/skills/example/SKILL.md").write_text("# Example\n\nUse the example script.\n")
        skill = self.commit("Describe the example skill")
        result = self.push("feature")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remote_head("feature"), skill)
        self.assertEqual(len(self.check_calls()), 2)

    def test_reuses_a_recent_pass_for_the_pushed_tree(self):
        subprocess.run([str(self.repo / "bin/check"), "--full"], cwd=self.repo, env=self.env, text=True,
                       capture_output=True, check=True)
        self.assertEqual(len(self.check_calls()), 1)
        result = self.push("main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.check_calls()), 1)


if __name__ == "__main__":
    unittest.main()
