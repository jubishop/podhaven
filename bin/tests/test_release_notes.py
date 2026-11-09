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
PROJECT = "PodHaven.xcodeproj/project.pbxproj"
RESOLVED = "PodHaven.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
SETTINGS = ("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {target};\n\t\t\t\tMARKETING_VERSION = {version};\n"
            "\t\t\t\tSWIFT_VERSION = 6.0;\n")
FAKE_LLM = r'''
import json, os, pathlib, sys
base = pathlib.Path(os.environ['NOTES_FIXTURE'])
with (base / 'llm-calls').open('a') as stream:
    stream.write(json.dumps([sys.argv[1:], sys.stdin.read()]) + '\n')
print('Thinking about the commits...', file=sys.stderr)
if os.environ.get('LLM_FAILS'):
    print('llm: model unavailable', file=sys.stderr)
    sys.exit(1)
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
                    "NOTES_FIXTURE": str(self.base), "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                    "TZ": "America/Los_Angeles"}
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

    def commit(self, path, message, date=None, text=None):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        if text is None:
            text = file.read_text() + message + "\n" if file.exists() else message + "\n"
        file.write_text(text)
        self.git("add", path)
        self.git_at(date, "commit", "-m", message)

    def git_at(self, date, *args):
        env = {**self.env, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date} if date else self.env
        subprocess.run(["git", "-C", str(self.repo), *args], env=env, check=True, capture_output=True)

    def add_untested_commits(self, app_commits):
        self.commit("PodHaven/Player.swift", "🐛 fix: Tested fix", "2026-10-20T12:00:00-07:00")
        self.git_at("2026-10-20T12:00:00-07:00", "tag", "-a", "v1.4.1b583", "-m", "Tested build")
        self.commit("docs/releases.md", "📝 docs: Explain release tooling", "2026-10-22T09:00:00-07:00")
        for day in range(app_commits):
            self.commit("PodHaven/Player.swift", f"🐛 fix(play): Untested fix {day + 1}\n\nDetail for fix {day + 1}.\n\n"
                        "Co-authored-by: Someone <someone@example.invalid>", f"2026-10-{24 + day}T12:00:00-07:00")

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

    def run_in_terminal(self, answer, args=("appstore", "--since-build", "582"), **env):
        if args[0] != "untested":
            self.commit("PodHaven/Player.swift", "🐛 fix: Another fix")
        controller, terminal = pty.openpty()
        try:
            process = subprocess.Popen([str(self.repo / "bin/release-notes"), *args],
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


    def test_untested_shows_a_few_commits_in_full_with_dates(self):
        self.add_untested_commits(2)
        result = self.run_notes("untested", "--since-build", "583")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.llm_calls())
        report = result.stderr
        self.assertIn("Testers in Everyone don't have 2 app commits yet.", report)
        self.assertIn("v1.4.1b583, went out Oct 20, 2026 at 12:00 PM PDT", report)
        self.assertIn("3 commits landed between Oct 22, 2026 and Oct 25, 2026, and 2 of them change the app.", report)
        for day in (1, 2):
            self.assertIn(f"Untested fix {day}", report)
            self.assertIn(f"Detail for fix {day}.", report)
        self.assertIn("Oct 24, 2026", report)
        self.assertNotIn("Co-authored-by", report)
        self.assertNotIn("Explain release tooling", report)
        self.assertIn("testflight", report)

    def test_untested_summarizes_more_than_three_commits(self):
        self.add_untested_commits(4)
        result = self.run_notes("untested", "--since-build", "583", LLM_OUTPUT="- Playback fixes touch the queue.")
        self.assertNotEqual(result.returncode, 0)
        [(args, log)] = self.llm_calls()
        self.assertIn("developer", args[args.index("-s") + 1])
        self.assertIn("Detail for fix 4.", log)
        self.assertIn("- Playback fixes touch the queue.", result.stderr)
        self.assertIn("4 app commits", result.stderr)
        for day in range(1, 5):
            self.assertIn(f"Untested fix {day}", result.stderr)
        self.assertNotIn("Detail for fix 1.", result.stderr)

    def test_llm_reasoning_stays_hidden_unless_the_call_fails(self):
        self.commit("PodHaven/Player.swift", "🐛 fix: Another fix")
        result = self.run_notes("testflight", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Thinking about the commits", result.stderr)
        result = self.run_notes("testflight", "--since-build", "582", LLM_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("llm: model unavailable", result.stderr)

    def test_untested_lists_commits_in_full_when_the_summary_fails(self):
        self.add_untested_commits(4)
        result = self.run_notes("untested", "--since-build", "583", LLM_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("llm: model unavailable", result.stderr)
        self.assertIn("Detail for fix 1.", result.stderr)
        self.assertIn("Detail for fix 4.", result.stderr)

    def pending(self, build="584", state="WAITING_FOR_BETA_REVIEW", submitted="2026-10-26T16:52:25-07:00"):
        path = self.base / "pending.json"
        path.write_text(json.dumps({"build": build, "version": "1.4.2", "state": state, "submitted": submitted}))
        return str(path)

    def test_untested_names_a_newer_build_waiting_for_beta_review(self):
        self.add_untested_commits(2)
        self.git("tag", "-a", "v1.4.2b584", "-m", "Waiting build")
        result = self.run_notes("untested", "--since-build", "583", "--pending", self.pending())
        self.assertNotEqual(result.returncode, 0)
        report = result.stderr
        self.assertIn("A newer build, 584 (1.4.2), hasn't reached them: Apple lists it as waiting for beta review.",
                      report)
        self.assertIn("It was submitted for review Oct 26, 2026 at 4:52 PM PDT (", report)
        self.assertIn("It includes every app commit below.", report)
        self.assertIn("Wait for Apple's beta review of build 584", report)
        self.assertNotIn("Run testflight first", report)

    def test_untested_says_which_commits_a_newer_build_has(self):
        self.add_untested_commits(2)
        self.git("tag", "-a", "v1.4.2b584", "-m", "Rejected build", "HEAD~1")
        for build, coverage in (("584", "It includes 1 of the 2 app commits below."), ("585", None)):
            with self.subTest(build=build):
                pending = self.pending(build=build, state="BETA_REJECTED", submitted=None)
                report = self.run_notes("untested", "--since-build", "583", "--pending", pending).stderr
                self.assertIn(f"A newer build, {build} (1.4.2), hasn't reached them: Apple lists it as beta rejected.",
                              report)
                self.assertNotIn("submitted for review", report)
                if coverage:
                    self.assertIn(coverage, report)
                else:
                    self.assertNotIn("It includes", report)
                self.assertIn("Run testflight first", report)

    def test_untested_without_a_newer_build_names_none(self):
        self.add_untested_commits(1)
        path = self.base / "pending.json"
        path.write_text("")
        report = self.run_notes("untested", "--since-build", "583", "--pending", str(path)).stderr
        self.assertIn("Testers in Everyone don't have 1 app commit yet.", report)
        self.assertNotIn("newer build", report)
        self.assertIn("Run testflight first", report)

    def test_untested_is_silent_when_testers_have_every_app_change(self):
        self.commit("docs/releases.md", "📝 docs: Explain release tooling")
        result = self.run_notes("untested", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout + result.stderr, "")
        self.assertFalse(self.llm_calls())

    def test_untested_reports_a_dependency_update_alone(self):
        self.add_untested_commits(0)
        self.commit(RESOLVED, "⬆️ chore(deps): Update Nuke", "2026-10-24T12:00:00-07:00")
        result = self.run_notes("untested", "--since-build", "583")
        self.assertNotEqual(result.returncode, 0)
        report = result.stderr
        self.assertIn("Testers in Everyone don't have 1 app commit yet.", report)
        self.assertIn("2 commits landed between Oct 22, 2026 and Oct 24, 2026, and 1 of them changes the app.", report)
        self.assertIn("Oct 24, 2026", report)
        self.assertIn("Update Nuke", report)
        self.assertIn("Run testflight first", report)

    def test_untested_counts_build_setting_changes_but_not_version_changes(self):
        self.commit(PROJECT, "🔧 build: Add the project", text=SETTINGS.format(target="26.1", version="1.4.1"))
        self.add_untested_commits(0)
        self.commit(PROJECT, "Change version number to 1.5", "2026-10-24T12:00:00-07:00",
                    text=SETTINGS.format(target="26.1", version="1.5"))
        self.commit(PROJECT, "🔧 build: Raise the deployment target", "2026-10-25T12:00:00-07:00",
                    text=SETTINGS.format(target="26.2", version="1.5"))
        self.git("tag", "-a", "v1.5b584", "-m", "Rejected build")
        self.commit(RESOLVED, "⬆️ chore(deps): Update Nuke", "2026-10-26T12:00:00-07:00")
        pending = self.pending(state="BETA_REJECTED", submitted=None)
        report = self.run_notes("untested", "--since-build", "583", "--pending", pending).stderr
        self.assertIn("Testers in Everyone don't have 2 app commits yet.", report)
        self.assertIn("4 commits landed between Oct 22, 2026 and Oct 26, 2026, and 2 of them change the app.", report)
        self.assertIn("Raise the deployment target", report)
        self.assertIn("Update Nuke", report)
        self.assertNotIn("Change version number", report)
        self.assertIn("It includes 1 of the 2 app commits below.", report)

    def test_notes_leave_dependency_and_build_setting_changes_to_the_fixed_note(self):
        self.commit(RESOLVED, "⬆️ chore(deps): Update Nuke")
        self.commit(PROJECT, "🔧 build: Raise the deployment target", text=SETTINGS.format(target="26.2", version="1.4.1"))
        result = self.run_notes("testflight", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "Behind-the-scenes stability and performance improvements.")
        self.assertFalse(self.llm_calls())
        self.commit("PodHaven/Player.swift", "🐛 fix: Another fix")
        result = self.run_notes("testflight", "--since-build", "582")
        self.assertEqual(result.returncode, 0, result.stderr)
        [(_, log)] = self.llm_calls()
        self.assertIn("Another fix", log)
        self.assertNotIn("Update Nuke", log)
        self.assertNotIn("deployment target", log)

    def test_untested_release_proceeds_only_on_yes(self):
        self.add_untested_commits(1)
        for answer, approved in ((b"y\n", True), (b"yes\n", True), (b"\n", False), (b"n\n", False)):
            with self.subTest(answer=answer):
                returncode, _ = self.run_in_terminal(answer, args=("untested", "--since-build", "583"))
                self.assertEqual(returncode == 0, approved)


if __name__ == "__main__":
    unittest.main()
