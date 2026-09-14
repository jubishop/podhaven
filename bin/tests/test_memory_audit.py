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
        return self.publish()

    def publish(self):
        result = self.command("bin/finalize-memory-audit", check=False, extra={
            "PUBLISH_CHANGES": "false", "AUDIT_OUTCOME": "success", "RUNNER_TEMP": str(self.base),
            "EXPECTED_HEAD_SHA": self.head})
        self.assertEqual(self.command("git", "rev-parse", "HEAD").stdout.strip(), self.head)
        return result

    def check_runner_transport(self, content, cost=0, should_succeed=True):
        for name in ("run-memory-audit.mjs", "memory-audit-prompt.md"):
            shutil.copy2(SOURCE / "bin" / name, self.repo / "bin" / name)
        (self.repo / "AGENTS.md").write_text("Audit fixture instructions.\n")
        self.command("git", "add", "bin", "AGENTS.md")
        self.command("git", "-c", "core.hooksPath=/dev/null", "commit", "-m", "Runner fixture")
        self.head = self.command("git", "rev-parse", "HEAD").stdout.strip()
        (self.repo / "artifacts/memory-audit-context.json").write_text(json.dumps({
            "baseSha": self.head, "activeNoteCount": 1, "issues": [], "pullRequests": [],
        }))
        report = "# Memory audit report\n\n- Active notes reviewed: 1\n\n## Per-note findings\n\nIncident reviewed.\n"
        calls = []
        if content is not None:
            calls.append(("write_memory_file", {
                "path": self.note.relative_to(self.repo).as_posix(), "content": content,
            }))
        calls.append(("write_report", {"content": report}))
        response = {"choices": [{"message": {"role": "assistant", "tool_calls": [
            {"id": str(index), "type": "function", "function": {
                "name": name, "arguments": json.dumps(args),
            }} for index, (name, args) in enumerate(calls)
        ]}}], "usage": {"cost": cost}}
        mock = self.repo / ".cache/openrouter.mjs"
        mock.parent.mkdir()
        mock.write_text(
            "import { writeFile } from 'node:fs/promises';\n"
            "let called = false;\n"
            "globalThis.fetch = async (url, options) => {\n"
            "  if (called) throw new Error('Unexpected second model request');\n"
            "  called = true;\n"
            "  await writeFile('.cache/request.json', options.body);\n"
            f"  return Response.json({json.dumps(response)});\n"
            "};\n")
        result = self.command("node", "--import", str(mock), "bin/run-memory-audit.mjs", check=False, extra={
            "OPENROUTER_API_KEY": "fixture-only", "OPENROUTER_MODEL": "", "MAX_AGENT_TURNS": "1",
            "MAX_API_COST_USD": "",
        })
        usage = json.loads((self.repo / "artifacts/openrouter-usage.json").read_text())
        if not should_succeed:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("cost limit exceeded", result.stderr)
            self.assertEqual(usage["status"], "failed")
            self.assertEqual(usage["maxCost"], 0.50)
            self.assertEqual(usage["totalCost"], cost)
            self.assertFalse((self.repo / "artifacts/memory-audit-report.md").exists())
            self.assertNotIn("MEMORY_AUDIT_PATCH_START", (self.repo / "artifacts/openrouter-final.md").read_text())
            self.command("git", "diff", "--exit-code", self.head, "--", "memory")
            return
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(usage["status"], "success")
        request = json.loads((self.repo / ".cache/request.json").read_text())
        self.assertEqual(request["model"], "deepseek/deepseek-v4.1-flash")
        if content is not None:
            self.assertEqual(self.note.read_text(), content)
        patch = self.command("git", "diff", self.head, "--binary", "--", "memory").stdout
        expected_note = self.note.read_text()
        self.command("git", "restore", "--staged", "--worktree", "memory")
        (self.repo / "artifacts/memory-audit-report.md").unlink()
        (self.repo / "artifacts/memory-audit-context.json").unlink()
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.base / "memory-audit/memory-audit.patch").read_bytes(), patch.encode())
        self.assertEqual(self.note.read_text(), expected_note)
        meta = json.loads((self.base / "memory-audit/run-meta.json").read_text())
        self.assertEqual(meta["health"], "ok")
        self.assertEqual(meta["reportSource"], "result")
        self.assertTrue(meta["patchValid"])
        self.assertIsNone(meta["prUrl"])

    def test_runner_preserves_trailing_blank_context(self):
        self.note.write_text(self.note.read_text() + "\n## Details\n\n")
        self.command("git", "add", "memory/incident.md")
        self.command("git", "-c", "core.hooksPath=/dev/null", "commit", "-m", "Blank context fixture")
        self.check_runner_transport(self.note.read_text().replace("A durable rule.", "An updated rule."))

    def test_runner_preserves_trailing_spaces_in_added_line(self):
        self.check_runner_transport(self.note.read_text() + "\nMore guidance.  \n")

    def test_runner_transports_empty_patch(self):
        self.check_runner_transport(None)

    def test_runner_allows_cost_above_former_guard(self):
        self.check_runner_transport(None, cost=0.30)

    def test_runner_stops_above_cost_guard(self):
        self.check_runner_transport(None, cost=0.51, should_succeed=False)

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
