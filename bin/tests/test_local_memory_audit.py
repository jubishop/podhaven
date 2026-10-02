"""Exercise the local audit with real disposable Git checkouts and fake services."""

import json
import fcntl
import os
from pathlib import Path
import shutil
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SOURCE / "bin"))
import _memory_audit as audit


class LocalAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="local audit ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        for name in ("bin", "memory/archive", "memory/sentry_feedback", "docs", ".config"):
            (self.repo / name).mkdir(parents=True, exist_ok=True)
        for name in ("knowledge-config", "_knowledge.py"):
            shutil.copy2(SOURCE / "bin" / name, self.repo / "bin" / name)
        shutil.copy2(SOURCE / ".config/knowledge.json", self.repo / ".config/knowledge.json")
        (self.repo / ".gitignore").write_text(".cache/\nartifacts/\n")
        (self.repo / "docs/README.md").write_text("# Docs\n")
        (self.repo / "memory/sentry_feedback/.gitkeep").touch()
        self.note = self.repo / "memory/incident.md"
        self.content = "---\nname: incident\ndescription: An incident.\ntype: project\nstatus: active\n---\n\n# Incident\n\nA durable rule.\n"
        self.note.write_text(self.content)
        (self.repo / "memory/README.md").write_text(
            "# Memory\n\nPreserve this policy.\n\n<!-- ACTIVE_MEMORY_START -->\n<!-- ACTIVE_MEMORY_END -->\n")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Audit test")
        self.git("config", "user.email", "test@example.invalid")
        audit.update_index(self.repo)
        self.git("add", ".")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "✅ test: Add memory audit fixture")
        self.git("remote", "add", "origin", str(self.repo))
        self.head = self.git("rev-parse", "HEAD")
        self.fake = self.base / "tools"
        self.fake.mkdir()
        self.result = {
            "report": "# Memory audit report\n\n- Active notes reviewed: 1\n\n## Per-note findings\n\nIncident checked against source.\n",
            "findings": [{"path": "memory/incident.md", "verdict": "keep", "evidence": "Current source retains the rule."}],
            "changes": [],
        }
        self.response = self.base / "response.json"
        self.calls = self.base / "calls.jsonl"
        self.executable("gh", "import json,sys\nprint(json.dumps([]))\n")
        self.executable("qmd", "print('Index ready')\n")
        self.executable("codex", (
            "import json,os,pathlib,sys\n"
            "prompt = '' if sys.argv[1:] == ['login','status'] else sys.stdin.read()\n"
            f"with open({str(self.calls)!r}, 'a') as f: f.write(json.dumps({{'args':sys.argv[1:], 'env':dict(os.environ), 'prompt':prompt}})+'\\n')\n"
            "if sys.argv[1:] == ['login','status']:\n print('Logged in using ChatGPT')\n"
            "else:\n"
            f" response=json.loads(pathlib.Path({str(self.response)!r}).read_text())\n"
            f" calls=[json.loads(x) for x in pathlib.Path({str(self.calls)!r}).read_text().splitlines()]\n"
            " if isinstance(response,list): response=response[sum('exec' in c['args'] for c in calls)-1]\n"
            " pathlib.Path(sys.argv[sys.argv.index('--output-last-message')+1]).write_text(json.dumps(response))\n"
            " print('{\"type\":\"turn.completed\"}')\n"
        ))
        self.env = patch.dict(os.environ, {"PATH": str(self.fake) + os.pathsep + os.environ["PATH"]})
        self.env.start()
        self.addCleanup(self.env.stop)

    def executable(self, name, body):
        path = self.fake / name
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o755)

    def git(self, *args, root=None):
        result = subprocess.run(["git", *args], cwd=root or self.repo, text=True,
                                capture_output=True, check=True)
        return result.stdout.strip()

    def run_audit(self, force=False):
        self.response.write_text(json.dumps(self.result))
        return audit.run(self.repo, force=force)

    def archive(self):
        self.result["findings"][0]["verdict"] = "archive"
        self.result["changes"] = [{"path": "memory/incident.md", "archive": True,
                                   "content": self.content.replace("status: active", "status: resolved")}]

    def test_archive_is_reviewable_without_touching_user_checkout(self):
        self.archive()
        self.note.write_text(self.content + "\nUncommitted user edit.\n")
        before = self.note.read_bytes()
        output = self.run_audit()
        self.assertEqual(output["status"], "success")
        self.assertEqual(self.note.read_bytes(), before)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.head)
        run_dir = Path(output["directory"])
        proposed = run_dir / "repository"
        self.assertFalse((proposed / "memory/incident.md").exists())
        self.assertIn("status: resolved", (proposed / "memory/archive/incident.md").read_text())
        self.assertIn("Preserve this policy.", (proposed / "memory/README.md").read_text())
        self.assertNotIn("](incident.md)", (proposed / "memory/README.md").read_text())
        self.assertIn("memory/archive/incident.md", (run_dir / "memory-audit.patch").read_text())
        self.git("apply", "--reverse", "--check", str(run_dir / "memory-audit.patch"), root=proposed)

    def test_unchanged_inputs_skip_luna_and_force_runs_again(self):
        self.run_audit()
        count = len(self.calls.read_text().splitlines())
        self.assertEqual(self.run_audit()["status"], "skipped")
        self.assertEqual(len(self.calls.read_text().splitlines()), count)
        self.assertEqual(self.run_audit(force=True)["status"], "success")
        self.assertGreater(len(self.calls.read_text().splitlines()), count)

    def test_subscription_only_read_only_luna_invocation(self):
        with patch.dict(os.environ, {"CODEX_API_KEY": "fixture-key", "OPENROUTER_API_KEY": "fixture-router"}):
            self.run_audit()
        call = json.loads(self.calls.read_text().splitlines()[-1])
        self.assertIn("gpt-6-luna", call["args"])
        self.assertIn("read-only", call["args"])
        self.assertIn("--ignore-user-config", call["args"])
        self.assertIn('forced_login_method="chatgpt"', call["args"])
        self.assertIn("allow_login_shell=false", call["args"])
        self.assertNotIn("CODEX_API_KEY", call["env"])
        self.assertNotIn("OPENROUTER_API_KEY", call["env"])

    def test_api_key_login_stops_before_model_request(self):
        self.executable("codex", "print('Logged in using an API key')\n")
        with self.assertRaisesRegex(RuntimeError, "ChatGPT"):
            self.run_audit()
        self.assertFalse((self.repo / ".cache/memory-audit/last-success.json").exists())

    def test_missing_note_coverage_rejects_result_and_keeps_failure_evidence(self):
        self.result["findings"] = []
        with self.assertRaisesRegex(ValueError, "every active note"):
            self.run_audit()
        state = self.repo / ".cache/memory-audit"
        self.assertEqual(json.loads((state / "latest.json").read_text())["status"], "failed")
        self.assertFalse((state / "last-success.json").exists())

    def test_disallowed_writes_and_archive_overwrites_are_rejected(self):
        for target in ("memory/README.md", "memory/new.md", "memory/../AGENTS.md", "docs/README.md"):
            with self.subTest(target=target):
                self.result["changes"] = [{"path": target, "archive": False, "content": self.content}]
                with self.assertRaisesRegex(ValueError, "existing active note"):
                    self.run_audit()
        self.archive()
        (self.repo / "memory/archive/incident.md").write_text("Existing archive\n")
        self.git("add", "memory/archive")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "✅ test: Add existing archive fixture")
        with self.assertRaisesRegex(ValueError, "existing archive"):
            self.run_audit()

    def test_invalid_metadata_or_links_block_success(self):
        for content in (self.content.replace("status: active", "status: resolved"),
                        self.content + "\n[Missing](missing.md)\n"):
            with self.subTest(content=content):
                self.result["changes"] = [{"path": "memory/incident.md", "archive": False, "content": content}]
                with self.assertRaisesRegex(ValueError, "status must be active|missing link"):
                    self.run_audit()

    def test_failed_model_does_not_export_patch_or_advance_success(self):
        self.executable("codex", "import sys\nprint('Logged in using ChatGPT')\n"
                        "sys.exit(0 if sys.argv[1:] == ['login','status'] else 1)\n")
        with self.assertRaises(RuntimeError):
            self.run_audit()
        state = self.repo / ".cache/memory-audit"
        meta = json.loads((state / "latest.json").read_text())
        self.assertFalse((Path(meta["directory"]) / "memory-audit.patch").exists())
        self.assertFalse((state / "last-success.json").exists())

    def test_lock_prevents_overlapping_audits(self):
        state = self.repo / ".cache/memory-audit"
        state.mkdir(parents=True)
        with (state / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.run_audit()["status"], "skipped")
        self.assertFalse(self.calls.exists())

    def test_github_activity_invalidates_change_gate(self):
        self.run_audit()
        self.executable("gh", "print('[{\"number\":1,\"state\":\"OPEN\",\"updatedAt\":\"2026-10-02T00:00:00Z\"}]')\n")
        self.assertEqual(self.run_audit()["status"], "success")

    def test_installer_registers_weekly_job_without_running_it(self):
        self.executable("launchctl", (
            "import json,sys\n"
            f"with open({str(self.calls)!r}, 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
            "sys.exit(1 if sys.argv[1] == 'print' else 0)\n"
        ))
        for name in ("plutil", "rg", "node"):
            self.executable(name, "pass\n")
        with patch.object(audit.sys, "platform", "darwin"), patch.object(Path, "home", return_value=self.base):
            result = audit.install(self.repo)
        settings = plistlib.loads(Path(result["plist"]).read_bytes())
        self.assertEqual(settings["StartCalendarInterval"], {"Weekday": 6, "Hour": 6, "Minute": 0})
        self.assertEqual(settings["ProgramArguments"][-2:], [str(self.repo / "bin/memory-audit"), "run"])
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual([call[0] for call in calls], ["print", "bootstrap", "enable"])

    def test_installed_path_can_run_qmd_with_its_separate_runtime(self):
        runtime = self.base / "runtime"
        runtime.mkdir()
        bun = runtime / "bun"
        bun.write_text(f"#!{sys.executable}\nprint('Runtime ready')\n")
        bun.chmod(0o755)
        self.executable("qmd", "import subprocess\nsubprocess.run(['bun'], check=True)\n")
        self.executable("launchctl", "import sys\nsys.exit(1 if sys.argv[1] == 'print' else 0)\n")
        self.executable("plutil", "pass\n")
        with patch.dict(os.environ, {"PATH": str(runtime) + os.pathsep + os.environ["PATH"]}), \
                patch.object(audit.sys, "platform", "darwin"), patch.object(Path, "home", return_value=self.base):
            result = audit.install(self.repo)
        settings = plistlib.loads(Path(result["plist"]).read_bytes())
        result = subprocess.run([str(self.fake / "qmd"), "--version"],
                                env=settings["EnvironmentVariables"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejected_archive_is_restored_before_one_repair_attempt(self):
        archived = self.repo / "memory/archive/older.md"
        archived.write_text("---\nname: older\ndescription: Older evidence.\ntype: reference\n---\n\n# Older\n\n[Incident](../incident.md)\n")
        self.git("add", "memory/archive")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "✅ test: Add an archived backlink fixture")
        self.archive()
        corrected = json.loads(json.dumps(self.result))
        corrected["findings"][0]["verdict"] = "keep"
        corrected["changes"] = []
        self.result = [self.result, corrected]
        output = self.run_audit()
        run_dir = Path(output["directory"])
        self.assertEqual(output["status"], "success")
        self.assertEqual((run_dir / "repository/memory/incident.md").read_text(), self.content)
        self.assertFalse((run_dir / "repository/memory/archive/incident.md").exists())
        self.assertEqual((run_dir / "memory-audit.patch").read_text(), "")
        self.assertTrue((run_dir / "rejected-result.json").exists())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(sum("exec" in call["args"] for call in calls), 2)
        self.assertIn("missing link destination ../incident.md", calls[-1]["prompt"])


if __name__ == "__main__":
    unittest.main()
