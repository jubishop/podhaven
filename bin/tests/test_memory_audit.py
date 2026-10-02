"""Keep the read-only document validation mode covered."""

import test_local_memory_audit as local
import shutil
import subprocess
import unittest


class AuditDocumentChecks(unittest.TestCase):
    def setUp(self):
        self.fixture = local.LocalAuditTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.repo = self.fixture.repo
        self.note = self.fixture.note
        (self.repo / "memory/archive").mkdir(exist_ok=True)
        for name in ("check", "_checks.py", "_memory_index.py"):
            shutil.copy2(local.SOURCE / "bin" / name, self.repo / "bin" / name)

    def command(self, *args, check=True):
        result = subprocess.run(args, cwd=self.repo, text=True, capture_output=True)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_audit_check_renders_index_without_writing_it(self):
        index = (self.repo / "memory/README.md").read_bytes()
        self.note.write_text(self.note.read_text().replace("status: active", "status: resolved"))
        self.command("git", "mv", "memory/incident.md", "memory/archive/incident.md")
        self.command("bin/check", "--memory-audit")
        self.assertEqual((self.repo / "memory/README.md").read_bytes(), index)
        result = self.command("bin/check", "--documents-only", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Active memory index is stale", result.stderr)

    def test_audit_check_still_validates_readme_policy_links(self):
        readme = self.repo / "memory/README.md"
        readme.write_text(readme.read_text() + "\n[Missing policy](missing.md)\n")
        index = readme.read_bytes()
        result = self.command("bin/check", "--memory-audit", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("memory/README.md: missing link destination missing.md", result.stderr)
        self.assertEqual(readme.read_bytes(), index)


if __name__ == "__main__":
    unittest.main()
