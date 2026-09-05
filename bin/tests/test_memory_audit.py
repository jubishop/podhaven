"""Validate publisher outcomes locally with publication disabled."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven audit ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        for name in ("bin", "memory/archive", "memory/sentry_feedback", "docs", ".config", "artifacts"):
            (self.repo / name).mkdir(parents=True, exist_ok=True)
        for name in ("finalize-memory-audit", "_checks.py", "_knowledge.py", "_memory_index.py", "check", "memory-index"):
            shutil.copy2(SOURCE / "bin" / name, self.repo / "bin" / name)
        shutil.copy2(SOURCE / ".config/knowledge.json", self.repo / ".config/knowledge.json")
        (self.repo / ".gitignore").write_text("artifacts/\n.cache/\n")
        self.note = self.repo / "memory/incident.md"
        self.note.write_text("---\nname: incident\ndescription: An incident.\ntype: project\nstatus: active\n---\n\n# Incident\n\nA durable rule.\n")
        (self.repo / "memory/README.md").write_text("# Memory\n\nKeep this policy byte for byte.\n\n<!-- ACTIVE_MEMORY_START -->\n<!-- ACTIVE_MEMORY_END -->\n")
        (self.repo / "docs/README.md").write_text("# Docs\n")
        self.command("git", "init", "-b", "main")
        self.command("git", "config", "user.name", "Audit test")
        self.command("git", "config", "user.email", "test@example.invalid")
        self.command("bin/memory-index")
        self.command("git", "add", ".")
        self.command("git", "-c", "core.hooksPath=/dev/null", "commit", "-m", "Fixture")
        self.head = self.command("git", "rev-parse", "HEAD").stdout.strip()

    def command(self, *args, check=True, extra=None):
        result = subprocess.run(args, cwd=self.repo, env=os.environ | (extra or {}), text=True,
                                capture_output=True, timeout=30)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def finalize(self):
        self.command("git", "add", "memory")
        patch = self.command("git", "diff", "--cached", "--no-renames", "--binary").stdout
        self.command("git", "restore", "--staged", "--worktree", "memory")
        report = "# Memory audit report\n\n- Active notes reviewed: 1\n\n## Per-note findings\n\nIncident reviewed.\n"
        (self.repo / "artifacts/openrouter-final.md").write_text(
            "<!-- MEMORY_AUDIT_REPORT_START -->\n" + report + "<!-- MEMORY_AUDIT_REPORT_END -->\n"
            "<!-- MEMORY_AUDIT_PATCH_START -->\n" + patch + "<!-- MEMORY_AUDIT_PATCH_END -->\n")
        result = self.command("bin/finalize-memory-audit", check=False, extra={
            "PUBLISH_CHANGES": "false", "AUDIT_OUTCOME": "success", "RUNNER_TEMP": str(self.base),
            "EXPECTED_HEAD_SHA": self.head})
        self.assertEqual(self.command("git", "rev-parse", "HEAD").stdout.strip(), self.head)
        return result

    def test_archive_regenerates_index_preserves_policy_and_never_publishes(self):
        self.note.write_text(self.note.read_text().replace("status: active", "status: resolved"))
        self.note.rename(self.repo / "memory/archive/incident.md")
        result = self.finalize()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        index = (self.repo / "memory/README.md").read_text()
        self.assertIn("Keep this policy byte for byte.", index)
        self.assertNotIn("](incident.md)", index)
        self.command("bin/check", "--documents-only")
        meta = json.loads((self.base / "memory-audit/run-meta.json").read_text())
        self.assertIsNone(meta["prUrl"])
        self.assertIn("memory/README.md", meta["changedFiles"])

    def test_invalid_metadata_and_broken_links_block_publication(self):
        for content in (self.note.read_text().replace("name: incident", "name: wrong"),
                        self.note.read_text() + "\n[Missing](missing.md)\n"):
            with self.subTest(content=content):
                self.command("git", "restore", "--staged", "--worktree", "memory")
                self.note.write_text(content)
                result = self.finalize()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("structure", result.stdout)

    def test_model_cannot_edit_index_policy(self):
        page = self.repo / "memory/README.md"
        page.write_text(page.read_text().replace("Keep this policy byte for byte.", "Discard policy."))
        result = self.finalize()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disallowed", result.stdout)
        self.assertIn("Keep this policy byte for byte.", page.read_text())


if __name__ == "__main__":
    unittest.main()
