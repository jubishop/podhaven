"""Test the copied foundation in disposable repositories; no network or models."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[2]


class KnowledgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="project starter tests ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "main checkout"
        self.repo.mkdir()
        for name in ("bin", "docs", "memory"):
            shutil.copytree(SOURCE / name, self.repo / name, ignore=shutil.ignore_patterns("__pycache__"))
        (self.repo / ".config").mkdir()
        shutil.copy2(SOURCE / ".config/knowledge.json", self.repo / ".config/knowledge.json")
        for name in ("README.md", "AGENTS.md", "LICENSE", ".gitignore", ".project-starter.json"):
            shutil.copy2(SOURCE / name, self.repo / name)
        if (SOURCE / ".envrc").exists():
            shutil.copy2(SOURCE / ".envrc", self.repo / ".envrc")
        # Copy only source files directly linked by the knowledge pages.
        sys.path.insert(0, str(SOURCE / "bin"))
        from _checks import link_targets, local_target
        for page in (SOURCE / "docs").rglob("*.md"):
            for target in link_targets(page.read_text()):
                resolved, _ = local_target(page, target)
                if resolved and resolved.is_file() and resolved.is_relative_to(SOURCE):
                    destination = self.repo / resolved.relative_to(SOURCE)
                    if not destination.exists():
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(resolved, destination)
        self.tools = self.base / "fake tools"
        self.tools.mkdir()
        for name, target in (("python3", sys.executable), ("git", shutil.which("git"))):
            (self.tools / name).symlink_to(target)
        self.events = self.base / "events.jsonl"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(PATH=str(self.tools), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        PYTHONDONTWRITEBYTECODE="1", EVENTS=str(self.events), APPROVALS=str(self.base / "approvals.jsonl"),
                        OLD_HOOKS=str(self.base / "old-hooks.jsonl"), QMD_CONFIG_DIR="/wrong-config",
                        XDG_CACHE_HOME="/wrong-cache", INDEX_PATH="/wrong-index")
        self.tool("qmd", '''
import json, os, sys, time
from pathlib import Path
if sys.argv[1:] == ["--version"]:
    if os.environ.get("BROKEN_QMD"):
        sys.exit(9)
    print("qmd 2.1.0 (test)")
    sys.exit(0)
record = {"command": sys.argv[1], "cwd": os.getcwd(),
          "config": os.environ["QMD_CONFIG_DIR"], "cache": os.environ["XDG_CACHE_HOME"],
          "index": os.environ["INDEX_PATH"], "arguments": sys.argv[2:]}
record["collections"] = json.loads((Path(record["config"]) / "index.yml").read_text())["collections"]
with open(os.environ["EVENTS"], "a") as stream:
    stream.write(json.dumps(record) + "\\n")
if sys.argv[1] in ("update", "embed"):
    time.sleep(float(os.environ.get("QMD_TEST_DELAY", "0.02")))
    if sys.argv[1] == "update" and os.environ.get("FAIL_UPDATE"):
        sys.exit(23)
    Path(record["index"]).touch()
else:
    print(json.dumps(record))
''')
        self.tool("direnv", '''
import json, os, sys
from pathlib import Path
if sys.argv[1:] == ["status", "--json"]:
    print(json.dumps({"state": {"foundRC": {"allowed": int(os.environ.get("DIRENV_ALLOWED", "0")), "path": str(Path.cwd() / ".envrc")}}}))
elif sys.argv[1:] == ["version"]:
    print("2.37.1")
else:
    with open(os.environ["APPROVALS"], "a") as stream:
        stream.write(json.dumps(sys.argv[1:]) + "\\n")
''')
        self.run_command("git", "init", "-b", "main")
        self.run_command("git", "config", "user.name", "Starter test")
        self.run_command("git", "config", "user.email", "test@example.invalid")

    def tool(self, name, body):
        path = self.tools / name
        path.write_text("#!" + sys.executable + "\n" + body)
        path.chmod(0o755)

    def run_command(self, *args, root=None, extra=None, check=True, input=None):
        result = subprocess.run(args, cwd=root or self.repo, env=self.env | (extra or {}),
                                text=True, capture_output=True, input=input, timeout=30)
        if check:
            self.assertEqual(result.returncode, 0, (args, result.stdout, result.stderr))
        return result

    def records(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()] if self.events.exists() else []

    def drain(self, root=None):
        self.run_command("bin/qmd-index", root=root)

    def commit(self):
        self.run_command("git", "add", ".")
        self.run_command("git", "commit", "-m", "Fixture")
        self.drain()

    def wait_for_command(self, count):
        deadline = time.monotonic() + 10
        while len(self.records()) < count:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.02)

    def tree_state(self):
        result = {}
        for base in (self.repo / ".cache", self.repo / ".config", self.repo / "bin"):
            if base.exists():
                for path in base.rglob("*"):
                    if path.is_file():
                        stat = path.stat()
                        result[str(path)] = (stat.st_mtime_ns, stat.st_size, path.read_bytes())
        return result

    def test_fresh_copy_setup_from_subdirectory_and_search_routing(self):
        self.run_command("../bin/setup", root=self.repo / "docs")
        record = self.records()[0]
        self.assertEqual(record["cwd"], str(self.repo))
        self.assertEqual(record["index"], str(self.repo / ".cache/qmd/index.sqlite"))
        self.assertEqual(set(record["collections"]), {"memory", "docs", "sentry-history"})
        self.assertIn("context", record["collections"]["docs"])
        result = self.run_command("../bin/knowledge", "search", "reference", root=self.repo / "docs")
        self.assertEqual(json.loads(result.stdout)["index"], record["index"])
        result = self.run_command("git", "knowledge", "search", "reference", root=self.repo / "docs")
        self.assertEqual(json.loads(result.stdout)["index"], record["index"])
        self.assertEqual(self.env["XDG_CACHE_HOME"], "/wrong-cache")
        if (self.repo / ".envrc").exists():
            self.assertNotIn("export XDG_CACHE_HOME", (self.repo / ".envrc").read_text())

    def test_ci_configuration_excludes_personal_notes_and_preserves_history_scope(self):
        home = self.base / "private notes"
        home.mkdir()
        self.run_command("git", "config", "knowledge.homeMemoryPath", str(home))
        result = json.loads(self.run_command("bin/knowledge-config", "--ci").stdout)
        self.assertNotIn("home-memory", result["collections"])
        self.assertFalse(result["collections"]["sentry-history"]["includeByDefault"])
        self.assertEqual(result["collections"]["memory"]["path"], str(self.repo / "memory"))
        self.assertFalse((self.repo / ".cache").exists())

    def test_default_setup_needs_no_environment_file(self):
        self.assertFalse((self.repo / ".envrc").exists())
        self.run_command("bin/setup")
        self.assertFalse((self.repo / ".envrc").exists())
        self.assertEqual(json.loads(self.run_command("bin/doctor", "--json").stdout)["freshness"], "current")

    def test_repeat_setup_and_code_only_changes_skip_qmd_work(self):
        self.run_command("bin/setup")
        before = list(self.records())
        self.run_command("bin/setup")
        (self.repo / "app.py").write_text("print('new code')\n")
        self.drain()
        self.assertEqual(self.records(), before)

    def test_both_optional_tools_absent(self):
        (self.tools / "qmd").unlink()
        (self.tools / "direnv").unlink()
        result = self.run_command("bin/setup")
        self.assertIn("absent", result.stdout)
        self.assertEqual(self.records(), [])
        report = json.loads(self.run_command("bin/doctor", "--json").stdout)
        self.assertEqual(report["freshness"], "unavailable")

    def test_installed_broken_qmd_is_not_reported_as_absent(self):
        result = self.run_command("bin/setup", extra={"BROKEN_QMD": "1"}, check=False)
        self.assertNotEqual(result.returncode, 0)
        report = json.loads(self.run_command("bin/doctor", "--json", extra={"BROKEN_QMD": "1"}, check=False).stdout)
        self.assertTrue(any("installed" in message for message in report["issues"]))

    def test_home_memory_edits_deletions_and_opt_out(self):
        home = self.base / 'home notes "quoted"'
        home.mkdir()
        note = home / "note.md"
        note.write_text("# Personal guidance\nFirst version\n")
        self.run_command("git", "config", "knowledge.homeMemoryPath", str(home))
        self.run_command("bin/setup")
        self.assertIn("home-memory", self.records()[-1]["collections"])
        initial = len(self.records())
        note.write_text("# Personal guidance\nSecond version\n")
        self.drain()
        note.unlink()
        self.drain()
        self.run_command("git", "config", "--unset", "knowledge.homeMemoryPath")
        self.drain()
        self.assertEqual(len(self.records()), initial + 6)
        self.assertNotIn("home-memory", self.records()[-1]["collections"])

    def test_missing_home_memory_notice_and_relative_path_rejection(self):
        self.run_command("git", "config", "knowledge.homeMemoryPath", str(self.base / "missing"))
        self.run_command("bin/setup")
        report = json.loads(self.run_command("bin/doctor", "--json").stdout)
        self.assertTrue(any("Home memory is missing" in item for item in report["notices"]))
        self.run_command("git", "config", "knowledge.homeMemoryPath", "relative")
        self.assertNotEqual(self.run_command("bin/setup", check=False).returncode, 0)

    def test_doctor_is_read_only_and_detects_uncommitted_edits(self):
        self.run_command("bin/setup")
        before = self.tree_state()
        report = json.loads(self.run_command("bin/doctor", "--json").stdout)
        self.assertEqual(report["freshness"], "current")
        self.assertEqual(before, self.tree_state())
        with (self.repo / "docs/development-workflow.md").open("a") as stream:
            stream.write("\nUncommitted change.\n")
        report = json.loads(self.run_command("bin/doctor", "--json", check=False).stdout)
        self.assertEqual(report["freshness"], "stale")
        result = self.run_command("bin/knowledge", "search", "change")
        self.assertIn("freshness", result.stderr)
        self.drain()
        self.run_command("bin/doctor")

    def test_missing_database_forces_rebuild(self):
        self.run_command("bin/setup")
        (self.repo / ".cache/qmd/index.sqlite").unlink()
        self.drain()
        self.assertEqual([r["command"] for r in self.records()], ["update", "embed"] * 2)

    def test_preserve_existing_configured_and_default_hooks(self):
        for configured in (False, True):
            with self.subTest(configured=configured):
                directory = self.repo / ("existing-hooks" if configured else ".git/hooks")
                directory.mkdir(exist_ok=True)
                hook = directory / "post-commit"
                hook.write_text("#!/bin/sh\nexit 0\n")
                hook.chmod(0o755)
                if configured:
                    self.run_command("git", "config", "core.hooksPath", "existing-hooks")
                result = self.run_command("bin/setup", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Existing hooks preserved", result.stderr)
                setting = self.run_command("git", "config", "--get", "core.hooksPath", check=False).stdout.strip()
                self.assertEqual(setting, "existing-hooks" if configured else "")
                self.assertEqual(hook.read_text(), "#!/bin/sh\nexit 0\n")

    def test_external_hook_integration_preserves_behavior_arguments_and_stdin(self):
        hooks = self.repo / "custom hooks"
        hooks.mkdir()
        for event in ("post-checkout", "post-commit", "post-merge", "post-rewrite"):
            path = hooks / event
            path.write_text("#!" + sys.executable + '''
import json, os, subprocess, sys
from pathlib import Path
event = Path(__file__).name
payload = sys.stdin.read() if event == "post-rewrite" else ""
with open(os.environ["OLD_HOOKS"], "a") as log:
    log.write(json.dumps({"event": event, "args": sys.argv[1:], "stdin": payload}) + "\\n")
subprocess.run([str(Path.cwd() / "bin/knowledge-hook"), event, *sys.argv[1:]], check=True)
sys.exit(int(os.environ.get("OLD_HOOK_EXIT", "0")))
''')
            path.chmod(0o755)
        self.run_command("git", "config", "core.hooksPath", "custom hooks")
        self.run_command("git", "config", "knowledge.hooks", "external")
        self.run_command("bin/setup")
        stdin_file = self.base / "rewritten commits"
        stdin_file.write_text("old new\n")
        for event, args in (("post-checkout", ["1" * 40, "2" * 40, "1"]), ("post-commit", []),
                            ("post-merge", ["0"]), ("post-rewrite", ["amend"])):
            self.run_command("git", "hook", "run", "--to-stdin=" + str(stdin_file), event, "--", *args)
        self.drain()
        originals = [json.loads(line) for line in (self.base / "old-hooks.jsonl").read_text().splitlines()]
        self.assertEqual(originals[-1]["args"], ["amend"])
        self.assertEqual(originals[-1]["stdin"], "old new\n")
        self.run_command("bin/doctor")
        result = self.run_command("git", "hook", "run", "post-commit", extra={"OLD_HOOK_EXIT": "7"}, check=False)
        self.assertEqual(result.returncode, 7)
        self.drain()
        self.assertEqual(self.run_command("git", "config", "--get", "core.hooksPath").stdout.strip(), "custom hooks")

    def test_worktree_with_separate_git_directory_shares_only_models(self):
        (self.repo / ".envrc").write_text("export APPLICATION_MODE=development\n")
        metadata = self.base / "metadata" / "repository.git"
        metadata.parent.mkdir()
        self.run_command("git", "init", "--separate-git-dir", str(metadata))
        self.run_command("bin/setup")
        self.commit()
        worktree = self.base / "linked checkout"
        self.run_command("git", "worktree", "add", "-b", "feature", str(worktree))
        self.drain(root=worktree)
        self.assertEqual((self.repo / ".cache/qmd/models").resolve(), (worktree / ".cache/qmd/models").resolve())
        self.assertEqual((worktree / ".cache/qmd/models").resolve(), metadata / "knowledge/models")
        self.assertFalse(os.path.samefile(self.repo / ".cache/qmd/index.sqlite", worktree / ".cache/qmd/index.sqlite"))
        self.assertEqual(json.loads(self.run_command("bin/doctor", "--json", root=worktree).stdout)["freshness"], "current")
        approvals = Path(self.env["APPROVALS"])
        before = approvals.read_text()
        (worktree / ".envrc").write_text("# Different environment\n")
        self.run_command("bin/prep-worktree", root=worktree)
        self.assertEqual(approvals.read_text(), before)
        (worktree / ".envrc").write_bytes((self.repo / ".envrc").read_bytes())
        self.run_command("bin/prep-worktree", root=worktree, extra={"DIRENV_ALLOWED": "1"})
        self.assertEqual(approvals.read_text(), before)
        self.run_command("git", "worktree", "remove", "--force", str(worktree))

    def test_existing_models_are_preserved_and_shared_with_worktree(self):
        models = self.repo / ".cache/qmd/models"
        models.mkdir(parents=True)
        (models / "existing.gguf").write_text("preserve")
        self.run_command("bin/setup")
        self.commit()
        worktree = self.base / "another checkout"
        self.run_command("git", "worktree", "add", "-b", "another", str(worktree))
        self.drain(root=worktree)
        self.assertEqual((worktree / ".cache/qmd/models").resolve(), models)
        self.assertEqual((models / "existing.gguf").read_text(), "preserve")
        self.run_command("git", "worktree", "remove", "--force", str(worktree))

    def test_burst_requests_coalesce_without_duplicate_qmd_pairs(self):
        self.run_command("bin/setup")
        self.events.unlink()
        (self.repo / ".cache/qmd/index.sqlite").unlink()
        processes = [subprocess.Popen([str(self.repo / "bin/qmd-index"), "--background"], cwd=self.repo,
                                      env=self.env | {"QMD_TEST_DELAY": "0.2"}, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(8)]
        for process in processes:
            output = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, output)
        self.drain()
        self.assertEqual([r["command"] for r in self.records()], ["update", "embed"])

    def test_edits_during_refresh_are_not_lost_without_another_hook(self):
        self.run_command("bin/setup")
        self.events.unlink()
        document = self.repo / "docs/development-workflow.md"
        document.write_text(document.read_text() + "\nFirst edit.\n")
        self.run_command("bin/qmd-index", "--background", extra={"QMD_TEST_DELAY": "0.3"})
        self.wait_for_command(1)
        document.write_text(document.read_text() + "\nSecond edit during refresh.\n")
        # Wait for the worker's own follow-up before enqueuing any foreground request.
        self.wait_for_command(4)
        self.drain()
        self.assertEqual([r["command"] for r in self.records()], ["update", "embed"] * 2)
        self.run_command("bin/doctor")

    def test_update_failure_skips_embed_and_releases_worker(self):
        result = self.run_command("bin/setup", extra={"FAIL_UPDATE": "1"}, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([r["command"] for r in self.records()], ["update"])
        report = json.loads(self.run_command("bin/doctor", "--json", check=False).stdout)
        self.assertEqual(report["last_refresh"]["status"], "failed")
        self.run_command("bin/qmd-index", "--force")
        self.run_command("bin/doctor")

    def test_collection_config_changes_and_archive_edits(self):
        self.run_command("bin/setup")
        initial = len(self.records())
        archive = self.repo / "memory/archive"
        archive.mkdir(exist_ok=True)
        (archive / "old.md").write_text("# Excluded\n")
        self.drain()
        self.assertEqual(len(self.records()), initial)
        path = self.repo / ".config/knowledge.json"
        config = json.loads(path.read_text())
        config["collections"]["docs"]["context"]["/"] = "Changed description"
        path.write_text(json.dumps(config))
        self.drain()
        self.assertEqual(len(self.records()), initial + 2)

    def test_check_modes_run_behavior_tests_only_with_full(self):
        self.tool("shellcheck", "import sys\nsys.exit(0)\n")
        suite = self.repo / Path(__file__).resolve().relative_to(SOURCE)
        # Replace only the disposable suite to observe execution without recursion.
        for path in suite.parent.glob("test_*.py"):
            path.unlink()
        suite.write_text("import unittest\nclass Probe(unittest.TestCase):\n"
                         "    def test_probe(self):\n"
                         "        self.fail('behavior suite executed')\n")
        fast = self.run_command("bin/check")
        self.assertIn("Fast foundation checks passed", fast.stdout)
        self.run_command("bin/check", "--documents-only")
        full = self.run_command("bin/check", "--full", check=False)
        self.assertNotEqual(full.returncode, 0)
        self.assertIn("behavior suite executed", full.stderr)
        suite.write_text(suite.read_text().replace("self.fail('behavior suite executed')", "pass"))
        self.assertIn("Full repository foundation checks passed", self.run_command("bin/check", "--full").stdout)
        suite.unlink()
        missing = self.run_command("bin/check", "--full", check=False)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("preserve the foundation tests", missing.stderr)

    def test_fast_check_still_rejects_syntax_and_lint_errors(self):
        self.tool("shellcheck", "import sys\nsys.exit(0)\n")
        suite = self.repo / Path(__file__).resolve().relative_to(SOURCE)
        for folder in (self.repo / "bin", suite.parent):
            with self.subTest(folder=folder):
                broken = folder / "invalid_syntax.py"
                broken.write_text("def broken(\n")
                self.run_command("bin/check", "--documents-only")
                result = self.run_command("bin/check", check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid_syntax.py", result.stderr)
                broken.unlink()
        self.tool("shellcheck", "import sys\nprint('shell lint failed', file=sys.stderr)\nsys.exit(1)\n")
        self.run_command("bin/check", "--documents-only")
        result = self.run_command("bin/check", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("shell lint failed", result.stderr)

    def test_fast_check_still_rejects_staged_whitespace(self):
        self.tool("shellcheck", "import sys\nsys.exit(0)\n")
        (self.repo / "whitespace.txt").write_text("trailing space \n")
        self.run_command("git", "add", "whitespace.txt")
        result = self.run_command("bin/check", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("trailing whitespace", result.stdout)

    def test_check_rejects_unknown_or_combined_modes(self):
        for args in (("--unknown",), ("--full", "--documents-only")):
            with self.subTest(args=args):
                result = self.run_command("bin/check", *args, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Usage:", result.stderr)

    def test_document_schema_names_and_index_coverage(self):
        self.run_command("bin/check", "--documents-only")
        page = self.repo / "memory/example.md"
        page.write_text('---\nname: wrong\ndescription: "A description: with punctuation."\ntype: reference\n---\n\n# Example\n')
        result = self.run_command("bin/check", "--documents-only", check=False)
        self.assertIn("must match", result.stderr)
        page.write_text(page.read_text().replace("name: wrong", "name: example"))
        result = self.run_command("bin/check", "--documents-only", check=False)
        self.assertIn("missing from", result.stderr)
        with (self.repo / "memory/README.md").open("a") as stream:
            stream.write("\n- [Example](example.md)\n")
        self.run_command("bin/memory-index")
        self.run_command("bin/check", "--documents-only")

    def test_archived_pages_cannot_remain_in_active_indexes(self):
        archive = self.repo / "memory/archive"
        archive.mkdir(exist_ok=True)
        (archive / "incident.md").write_text("---\nname: incident\ndescription: Resolved incident.\ntype: project\nstatus: resolved\n---\n\n# Incident\n")
        with (self.repo / "memory/README.md").open("a") as stream:
            stream.write("\n- [Old incident](archive/incident.md)\n")
        result = self.run_command("bin/check", "--documents-only", check=False)
        self.assertIn("archived page in active index", result.stderr)

    def test_heading_anchors_spaces_parentheses_and_reference_links(self):
        page = self.repo / "docs/notes (v2).md"
        page.write_text("---\nstatus: current\n---\n\n# Notes\n\n## Details\n\n## Details\n\n<a id=\"explicit\"></a>\n")
        index = self.repo / "docs/README.md"
        with index.open("a") as stream:
            stream.write('\n- [Notes](<notes (v2).md#details-1>)\n- [Details][note]\n\n[note]: <notes (v2).md#explicit> "Reference"\n')
        self.run_command("bin/check", "--documents-only")
        index.write_text(index.read_text().replace("#details-1", "#missing"))
        self.assertIn("missing heading anchor", self.run_command("bin/check", "--documents-only", check=False).stderr)

    def test_unsupported_metadata_and_generated_exclusions(self):
        page = self.repo / "docs/invalid.md"
        for content in ("status: current\nstatus: draft", "status: current\n  nested: value", "status: |\n  current"):
            with self.subTest(content=content):
                page.write_text("---\n" + content + "\n---\n\n# Invalid\n")
                self.assertNotEqual(self.run_command("bin/check", "--documents-only", check=False).returncode, 0)
        page.unlink()
        generated = self.repo / "docs/generated"
        generated.mkdir()
        (generated / "automatic.md").write_text("No metadata. [bad](missing.md)\n")
        path = self.repo / ".config/knowledge.json"
        config = json.loads(path.read_text())
        config["checks"]["exclude"].append("docs/generated/**")
        config["collections"]["docs"]["ignore"].append("generated/**")
        path.write_text(json.dumps(config))
        self.run_command("bin/check", "--documents-only")


if __name__ == "__main__":
    unittest.main()
