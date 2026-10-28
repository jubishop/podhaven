"""Generate release notes from real Git history with a fake LLM."""

import json
import os
from pathlib import Path
import pty
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
FAKE_LLM = r'''
import json, os, pathlib, sys
base = pathlib.Path(os.environ['NOTES_FIXTURE'])
with (base / 'llm-calls').open('a') as stream:
    stream.write(json.dumps([sys.argv[1:], sys.stdin.read()]) + '\n')
print(os.environ.get('LLM_OUTPUT', 'Playback skips less in CarPlay.'))
'''
FAKE_EDITOR = r'''
import os, pathlib, sys
path = pathlib.Path(sys.argv[-1])
with (pathlib.Path(os.environ['NOTES_FIXTURE']) / 'editor-input').open('a') as stream:
    stream.write(path.read_text())
path.write_text(os.environ['EDITED_NOTES'])
'''


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven release notes ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        shutil.copy2(ROOT / "bin/release-notes", self.repo / "bin/release-notes")
        commands = self.base / "commands"
        commands.mkdir()
        llm = commands / "llm"
        llm.write_text(f"#!{sys.executable}\n" + FAKE_LLM)
        llm.chmod(0o755)
        editor = commands / "fake-editor"
        editor.write_text(f"#!{sys.executable}\n" + FAKE_EDITOR)
        editor.chmod(0o755)
        self.env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "NOTES_FIXTURE": str(self.base), "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "LLM_OUTPUT", "VISUAL", "EDITOR"):
            self.env.pop(key, None)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Notes Test")
        self.git("config", "user.email", "notes@example.invalid")
        self.commit("PodHaven/Player.swift", "✨ feat(play): Add a sleep timer")
        self.git("tag", "-a", "v1.4b581", "-m", "App Store build")
        self.commit("PodHaven/Player.swift", "🐛 fix(carplay): Stop audio skipping in CarPlay")
        self.git("tag", "-a", "v1.4.1b582", "-m", "Tested build")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], env=self.env,
                                       stderr=subprocess.PIPE, text=True).strip()

    def commit(self, path, message):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(file.read_text() + message + "\n" if file.exists() else message + "\n")
        self.git("add", path)
        self.git("commit", "-m", message)

    def run_notes(self, *args, **env):
        return subprocess.run([str(self.repo / "bin/release-notes"), *args], cwd=self.repo,
                              env={**self.env, **env}, text=True, capture_output=True, timeout=15)

    def llm_calls(self):
        path = self.base / "llm-calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_summarizes_only_app_commits_since_the_base_build(self):
        self.commit("PodHavenWidget/Widget.swift", "🐛 fix(widget): Show the current episode artwork")
        self.commit("docs/releases.md", "📝 docs: Explain release tooling")
        self.commit("bin/check", "🐛 fix(tooling): Speed up local checks")
        result = self.run_notes("testflight", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Playback skips less in CarPlay.")
        self.assertIn("Playback skips less in CarPlay.", result.stderr)
        [(args, log)] = self.llm_calls()
        self.assertIn("Show the current episode artwork", log)
        self.assertNotIn("Stop audio skipping", log)
        self.assertNotIn("Explain release tooling", log)
        self.assertNotIn("Speed up local checks", log)
        self.assertIn("TestFlight", args[args.index("-s") + 1])

    def test_app_store_notes_cover_every_build_since_the_live_release(self):
        self.commit("PodHavenIntents/Intent.swift", "✨ feat(siri): Resume playback with Siri")
        result = self.run_notes("appstore", "--since-build", "581")
        self.assertEqual(result.returncode, 0, result.stderr)
        [(args, log)] = self.llm_calls()
        self.assertIn("Stop audio skipping", log)
        self.assertIn("Resume playback with Siri", log)
        self.assertNotIn("Add a sleep timer", log)
        self.assertIn("App Store", args[args.index("-s") + 1])

    def test_notes_end_at_the_requested_revision(self):
        self.commit("PodHaven/Later.swift", "✨ feat: Unreleased later work")
        result = self.run_notes("testflight", "--since-build", "581", "--to", "v1.4.1b582")
        self.assertEqual(result.returncode, 0, result.stderr)
        [(_, log)] = self.llm_calls()
        self.assertIn("Stop audio skipping", log)
        self.assertNotIn("Unreleased later work", log)

    def test_no_app_changes_use_a_fixed_note_without_the_llm(self):
        self.commit("docs/releases.md", "📝 docs: Explain release tooling")
        result = self.run_notes("testflight", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Behind-the-scenes stability and performance improvements.")
        self.assertFalse(self.llm_calls())

    def test_unknown_or_unrelated_base_builds_stop_without_notes(self):
        self.git("checkout", "--orphan", "other")
        self.commit("PodHaven/Other.swift", "Unrelated history")
        self.git("tag", "-a", "v9.9.9b900", "-m", "Unrelated build")
        self.git("checkout", "main")
        for build in ("599", "900", "58"):
            with self.subTest(build=build):
                result = self.run_notes("testflight", "--since-build", build)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--notes", result.stderr)
                self.assertEqual(result.stdout, "")
        self.assertFalse(self.llm_calls())

    def test_blank_or_oversized_llm_output_stops(self):
        self.commit("PodHaven/Player.swift", "🐛 fix: Another fix")
        for output in ("  ", "a" * 4001):
            with self.subTest(output=output[:5]):
                result = self.run_notes("testflight", "--since-build", "582", LLM_OUTPUT=output)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def run_in_terminal(self, answer, **env):
        self.commit("PodHaven/Player.swift", "🐛 fix: Another fix")
        controller, terminal = pty.openpty()
        try:
            process = subprocess.Popen([str(self.repo / "bin/release-notes"), "appstore", "--since-build", "582"],
                                       cwd=self.repo, env={**self.env, **env}, stdin=terminal, stderr=terminal,
                                       stdout=subprocess.PIPE, text=True)
            os.close(terminal)
            os.write(controller, answer)
            drain = threading.Thread(target=self.drain, args=(controller,), daemon=True)
            drain.start()
            stdout, _ = process.communicate(timeout=15)
            drain.join(timeout=5)
        finally:
            os.close(controller)
        return process.returncode, stdout

    @staticmethod
    def drain(controller):
        try:
            while os.read(controller, 4096):
                pass
        except OSError:
            pass

    def test_terminal_runs_continue_after_approval(self):
        for answer in (b"\n", b"y\n", b"Yes\n"):
            with self.subTest(answer=answer):
                returncode, stdout = self.run_in_terminal(answer)
                self.assertEqual(returncode, 0)
                self.assertEqual(stdout.strip(), "Playback skips less in CarPlay.")

    def test_terminal_runs_can_edit_the_generated_notes(self):
        edited = "• Siri handles much bigger libraries.\n• CarPlay skips less.\n"
        returncode, stdout = self.run_in_terminal(b"e\ny\n", EDITOR="fake-editor --wait",
                                                  EDITED_NOTES=edited)
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, edited)
        self.assertEqual((self.base / "editor-input").read_text(), "Playback skips less in CarPlay.\n")

    def test_edited_notes_must_be_usable(self):
        returncode, stdout = self.run_in_terminal(b"e\n", EDITOR="fake-editor", EDITED_NOTES=" \n")
        self.assertNotEqual(returncode, 0)
        self.assertEqual(stdout, "")
        returncode, stdout = self.run_in_terminal(b"e\ny\nn\n", EDITOR="fake-editor", EDITED_NOTES="a" * 4001)
        self.assertNotEqual(returncode, 0)
        self.assertEqual(stdout, "")

    def test_terminal_runs_stop_when_notes_are_declined(self):
        for answer in (b"n\n", b"no\n", b"\x04"):
            with self.subTest(answer=answer):
                returncode, stdout = self.run_in_terminal(answer)
                self.assertNotEqual(returncode, 0)
                self.assertEqual(stdout, "")


if __name__ == "__main__":
    unittest.main()
