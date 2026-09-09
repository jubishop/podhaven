"""Exercise the release command with real Git and fake external services."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FAKE = r'''
import json, os, pathlib, re, sys
base = pathlib.Path(os.environ['APPSTORE_FIXTURE'])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with (base / 'events').open('a') as stream:
    stream.write(json.dumps([name, args, os.environ.get('PODHAVEN_APPSTORE_NOTES'),
                             os.environ.get('ASC_KEY_PATH')]) + '\n')
if name == 'fastlane':
    mode = next(arg.split(':', 1)[1] for arg in args if arg.startswith('mode:'))
    if os.environ.get('APPSTORE_FAIL_PHASE') == mode:
        print('Apple failure during ' + mode, file=sys.stderr)
        sys.exit(23)
    if mode == 'notes':
        pathlib.Path(os.environ['PODHAVEN_APPSTORE_NOTES_PATH']).write_text(
            os.environ.get('LATEST_TESTFLIGHT_NOTES', 'Notes from TestFlight'))
    print('Confirmed ' + mode)
elif name == 'xcodebuild':
    if '-showdestinations' in args:
        print('{ platform:iOS Simulator, OS:26.5, name:iPhone 17 }')
    elif '-showBuildSettings' in args:
        source = (base / 'repo/PodHaven.xcodeproj/project.pbxproj').read_text()
        print('    MARKETING_VERSION = ' + re.search(r'MARKETING_VERSION = ([^;]+);', source)[1])
    elif '-exportArchive' in args and os.environ.get('FAIL_UPLOAD'):
        sys.exit(42)
elif name == 'llm':
    sys.stdin.read()
    print('Generated release notes')
elif name == 'xcbeautify':
    print(sys.stdin.read(), end='')
elif name == 'mktemp':
    path = base / 'logs'
    path.mkdir(exist_ok=True)
    print(path)
elif name == 'gh':
    if args[:2] == ['release', 'create'] and os.environ.get('CORRUPT_RECEIPT'):
        (base / 'repo/.git/podhaven-last-upload').write_text('v9.9b999\n')
elif name == 'rm':
    pass
else:
    raise SystemExit('Unexpected command: ' + name)
'''


class AppStoreCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven appstore ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        (self.repo / "PodHaven.xcodeproj").mkdir()
        self.project = self.repo / "PodHaven.xcodeproj/project.pbxproj"
        self.project.write_text("\tMARKETING_VERSION = 1.0.1;\n\tOTHER = keep;\n")
        for name in ("appstore", "version", "deploy.sh"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        (self.repo / "bin/shipit").symlink_to("deploy.sh")
        commands = self.base / "commands"
        commands.mkdir()
        for name in ("fastlane", "xcodebuild", "llm", "xcbeautify", "mktemp", "gh", "rm"):
            path = commands / name
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "APPSTORE_FIXTURE": str(self.base), "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_CONFIG_GLOBAL": os.devnull}
        for key in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID", "PODHAVEN_APPSTORE_NOTES",
                    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "Initial fixture")
        self.git("tag", "-a", "v1.0.1b569", "-m", "Previous build")
        remote = self.base / "remote.git"
        self.git("init", "--bare", str(remote))
        for name in ("origin", "sourcehut"):
            self.git("remote", "add", name, str(remote))
        self.git("push", "-u", "origin", "main")
        self.initial = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], env=self.env,
                                       stderr=subprocess.PIPE, text=True).strip()

    def run_command(self, *args, **env):
        return subprocess.run([sys.executable, str(self.repo / "bin/appstore"), *args],
                              cwd=self.base, env={**self.env, **env}, text=True,
                              capture_output=True, timeout=20)

    def events(self, name=None):
        path = self.base / "events"
        events = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [event for event in events if name is None or event[0] == name]

    def test_status_is_read_only_for_current_version(self):
        result = self.run_command("--status", PODHAVEN_APPSTORE_NOTES="stale inherited text")
        self.assertEqual(result.returncode, 0, result.stderr)
        event = self.events("fastlane")[0]
        self.assertEqual(event[1], ["manage_appstore", "mode:status", "version:1.0.1"])
        self.assertIsNone(event[2])
        self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)
        self.assertFalse(self.git("status", "--porcelain"))

    def test_default_releases_with_latest_testflight_notes(self):
        notes = 'Fixed playback.\nLiteral $HOME and `text`.'
        result = self.run_command(LATEST_TESTFLIGHT_NOTES=notes)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.events("fastlane")
        self.assertIn("mode:notes", calls[0][1])
        self.assertTrue(all(call[2] == notes for call in calls[1:]))
        self.assertIn("version:1.1", calls[-1][1])

    def test_release_override_can_use_testflight_notes(self):
        result = self.run_command("--release", "2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version:2", self.events("fastlane")[-1][1])
        self.assertEqual(self.events("fastlane")[-1][2], "Notes from TestFlight")

    def test_missing_or_invalid_testflight_notes_stop_before_changes(self):
        for notes in ("", "  \n", "a" * 4001):
            with self.subTest(notes=notes[:10]):
                result = self.run_command(LATEST_TESTFLIGHT_NOTES=notes)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--notes", result.stderr)
                self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)
                self.assertFalse(self.events("xcodebuild"))

    def test_notes_lookup_failure_stops_before_changes(self):
        result = self.run_command(APPSTORE_FAIL_PHASE="notes")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)
        self.assertFalse(self.events("xcodebuild"))

    def test_retry_keeps_saved_notes_even_when_testflight_changes(self):
        result = self.run_command(APPSTORE_FAIL_PHASE="submit")
        self.assertEqual(result.returncode, 23, result.stderr)
        result = self.run_command(LATEST_TESTFLIGHT_NOTES="Newer notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.events("fastlane")
        self.assertEqual(sum("mode:notes" in call[1] for call in calls), 1)
        self.assertEqual(calls[-1][2], "Notes from TestFlight")
        self.assertIn("version:1.1", calls[-1][1])

    def test_release_bumps_commits_uploads_and_submits_exact_build(self):
        notes = 'Fixed "playback".\nLiteral $HOME and `text`.'
        result = self.run_command("--release", "1.1", "--notes", notes)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.events("fastlane")
        self.assertEqual(calls[0][1], ["manage_appstore", "mode:preflight", "version:1.1"])
        self.assertEqual(calls[-1][1], ["manage_appstore", "mode:submit", "version:1.1", "build:570"])
        self.assertTrue(all(call[2] == notes for call in calls))
        self.assertEqual(self.project.read_text(), "\tMARKETING_VERSION = 1.1;\n\tOTHER = keep;\n")
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        self.assertEqual(self.git("diff", "--name-only", self.initial, "HEAD"),
                         "PodHaven.xcodeproj/project.pbxproj")
        self.assertFalse(self.git("status", "--porcelain"))
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))

    def test_notes_alone_release_the_next_minor_version(self):
        result = self.run_command("--notes", "Public notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version:1.1", self.events("fastlane")[-1][1])
        self.assertIn("MARKETING_VERSION = 1.1;", self.project.read_text())
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))

    def test_automatic_versions_increment_minor_and_discard_patch(self):
        for current, expected in (("2", "2.1"), ("2.1", "2.2"), ("2.2.3", "2.3"), ("2.9.9", "2.10")):
            with self.subTest(current=current):
                result = subprocess.run([str(self.repo / "bin/version"), current], cwd=self.repo,
                                        env=self.env, text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                result = self.run_command("--notes", "Release from " + current)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("version:" + expected, self.events("fastlane")[-1][1])
                self.assertIn("MARKETING_VERSION = " + expected + ";", self.project.read_text())

    def test_automatic_retry_keeps_the_uploaded_build(self):
        result = self.run_command("--notes", "Fixes", APPSTORE_FAIL_PHASE="submit")
        self.assertEqual(result.returncode, 23, result.stderr)
        result = self.run_command("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events("fastlane")[-1][1],
                         ["manage_appstore", "mode:submit", "version:1.1", "build:570"])
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")

    def test_automatic_retry_keeps_the_version_after_a_failed_push(self):
        hook = self.base / "remote.git/hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        result = self.run_command("--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MARKETING_VERSION = 1.1;", self.project.read_text())
        self.assertFalse(self.events("xcodebuild"))
        hook.unlink()
        result = self.run_command("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version:1.1", self.events("fastlane")[-1][1])
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")

    def test_repeating_a_completed_automatic_release_does_not_bump_again(self):
        for _ in range(2):
            result = self.run_command("--notes", "Fixes")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("version:1.1", self.events("fastlane")[-1][1])
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")

    def test_new_work_after_an_automatic_release_selects_the_next_minor(self):
        self.assertEqual(self.run_command("--notes", "Fixes").returncode, 0)
        (self.repo / "new-work.txt").write_text("Next release")
        self.git("add", "new-work.txt")
        self.git("commit", "-m", "New work")
        result = self.run_command("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version:1.2", self.events("fastlane")[-1][1])

    def test_automatic_retry_rejects_changed_notes(self):
        result = self.run_command("--notes", "Fixes", APPSTORE_FAIL_PHASE="submit")
        self.assertEqual(result.returncode, 23, result.stderr)
        count = len(self.events())
        result = self.run_command("--notes", "Different notes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same --notes", result.stderr)
        self.assertEqual(len(self.events()), count)

    def test_explicit_new_release_must_be_strictly_greater_than_current_version(self):
        result = subprocess.run([str(self.repo / "bin/version"), "2.1.0"], cwd=self.repo,
                                env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        for version in ("2", "2.0", "2.1"):
            for build in ([], ["--build", "600"]):
                with self.subTest(version=version, build=build):
                    result = self.run_command("--release", version, "--notes", "Fixes", *build)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("greater than", result.stderr)
                    self.assertFalse(self.events())

    def test_preparing_release_does_not_accept_unrelated_commits_on_retry(self):
        hook = self.base / "remote.git/hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        self.run_command("--notes", "Fixes")
        (self.repo / "unrelated.txt").write_text("Later work")
        self.git("add", "unrelated.txt")
        self.git("commit", "-m", "Later work")
        hook.unlink()
        count = len(self.events())
        result = self.run_command("--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checkout changed", result.stderr.lower())
        self.assertEqual(len(self.events()), count)

    def test_shipit_automatically_starts_the_next_testflight_version(self):
        result = self.run_command("--release", "1.1", "--notes", "Release notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(self.repo / "bin/shipit")], cwd=self.repo, env=self.env,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MARKETING_VERSION = 1.1.1;", self.project.read_text())
        self.assertEqual(self.git("log", "-1", "--format=%s"), "Change version number to 1.1.1")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.git("rev-parse", "origin/main"))
        self.assertEqual(self.git("rev-parse", "v1.1.1b571^{commit}"), self.git("rev-parse", "HEAD"))

    def test_shipit_uses_zero_minor_for_a_major_only_release(self):
        result = self.run_command("--release", "2", "--notes", "Release notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([str(self.repo / "bin/shipit")], cwd=self.repo, env=self.env,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MARKETING_VERSION = 2.0.1;", self.project.read_text())

    def test_shipit_retries_a_failed_version_push_before_uploading(self):
        self.assertEqual(self.run_command("--release", "1.1", "--notes", "Release notes").returncode, 0)
        hook = self.base / "remote.git/hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        for _ in range(2):
            result = subprocess.run([str(self.repo / "bin/shipit")], cwd=self.repo, env=self.env,
                                    text=True, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        hook.unlink()
        result = subprocess.run([str(self.repo / "bin/shipit")], cwd=self.repo, env=self.env,
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "3")

    def test_submission_retry_preserves_build_even_after_another_upload(self):
        result = self.run_command("--release", "1.1", "--notes", "Fixes", APPSTORE_FAIL_PHASE="submit")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertIn("retry", result.stderr.lower())
        (self.repo / "later.txt").write_text("Later development")
        self.git("add", "later.txt")
        self.git("commit", "-m", "Later change")
        self.git("tag", "-a", "v1.1b571", "-m", "Later upload")
        (self.repo / ".git/podhaven-last-upload").write_text("v1.1b571\n")
        result = self.run_command("--release", "1.1", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("build:570", self.events("fastlane")[-1][1])
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "3")

    def test_upload_failure_retries_without_another_version_commit(self):
        result = self.run_command("--release", "1.1", "--notes", "Fixes", FAIL_UPLOAD="1")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse(any("mode:submit" in event[1] for event in self.events("fastlane")))
        result = self.run_command("--release", "1.1", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-list", "--count", "HEAD"), "2")
        self.assertIn("build:570", self.events("fastlane")[-1][1])

    def test_preflight_failure_does_not_change_or_upload_the_project(self):
        result = self.run_command("--release", "1.1", "--notes", "Fixes", APPSTORE_FAIL_PHASE="preflight")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)
        self.assertFalse(self.git("status", "--porcelain"))
        self.assertFalse(self.events("xcodebuild"))

    def test_dirty_tree_or_feature_branch_stops_before_contacting_apple(self):
        (self.repo / "unrelated.txt").write_text("User work")
        result = self.run_command("--release", "1.1", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events())
        (self.repo / "unrelated.txt").unlink()
        self.git("checkout", "-b", "feature")
        result = self.run_command("--release", "1.1", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events())

    def test_retry_rejects_changed_notes_or_another_unfinished_release(self):
        self.run_command("--release", "1.1", "--notes", "Fixes", APPSTORE_FAIL_PHASE="submit")
        count = len(self.events())
        for version, notes in (("1.1", "Different notes"), ("1.2", "Fixes")):
            result = self.run_command("--release", version, "--notes", notes)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(len(self.events()), count)

    def test_wrong_upload_receipt_is_never_submitted(self):
        result = self.run_command("--release", "1.1", "--notes", "Fixes", CORRUPT_RECEIPT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("mode:submit" in event[1] for event in self.events("fastlane")))

    def test_explicit_uploaded_build_requires_release_and_skips_upload(self):
        result = self.run_command("--release", "2.0", "--notes", "Fixes", "--build", "568")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events("fastlane")[-1][1],
                         ["manage_appstore", "mode:submit", "version:2.0", "build:568"])
        self.assertFalse(self.events("xcodebuild"))
        self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)

    def test_bad_arguments_do_not_contact_apple_or_change_files(self):
        for args in (("--notes", ""), ("--notes", "Fixes", "--build", "569"),
                     ("--status", "--release", "1.1"), ("--status", "--notes", "Fixes"),
                     ("--release", "1.1", "--notes", ""),
                     ("--release", "1.1", "--notes", "a" * 4001), ("--build", "569"),
                     ("--release", "1.1", "--notes", "Fix", "--build", "latest"),
                     ("--release", "1.1;OTHER", "--notes", "Fix"),
                     ("--release", "1.1.1", "--notes", "Fix"),
                     ("--release", "1.1.1", "--notes", "Fix", "--build", "569"),
                     ("--release", "1.0", "--notes", "Fix"), ("--api-key-id", "key")):
            with self.subTest(args=args[:2]):
                result = self.run_command(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.events())
                self.assertEqual(self.git("rev-parse", "HEAD"), self.initial)
                self.assertFalse(self.git("status", "--porcelain"))

    def test_release_accepts_a_major_version_without_dots(self):
        result = self.run_command("--release", "2", "--notes", "Major release")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version:2", self.events("fastlane")[-1][1])

    def test_help_does_not_contact_apple(self):
        result = self.run_command("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--release", result.stdout)
        self.assertFalse(self.events())

    def test_existing_api_key_flags_and_failure_exit_are_preserved(self):
        (self.base / "key.p8").write_text("fake key")
        result = self.run_command("--status", "--api-key", "key.p8", "--api-key-id", "key",
                                  "--api-issuer-id", "issuer", APPSTORE_FAIL_PHASE="status")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(self.events("fastlane")[0][3], str(self.base / "key.p8"))

    def test_parallel_release_is_rejected(self):
        with (self.repo / ".git/podhaven-appstore.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_command("--release", "1.1", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events())


if __name__ == "__main__":
    unittest.main()
