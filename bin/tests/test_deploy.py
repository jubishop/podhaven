"""Run the deploy script with fake external commands and no release side effects."""

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
import json, os, pathlib, re, sys, tempfile
base = pathlib.Path(os.environ['DEPLOY_FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (base / 'events').open('a') as log:
    log.write(json.dumps([name, args, os.environ.get('PODHAVEN_TESTFLIGHT_NOTES')]) + '\n')
if name == 'git':
    args = args[2:] if args[:1] == ['-C'] else args
    state_path = base / 'state'
    state = json.loads(state_path.read_text())
    if args[0] == 'status': pass
    elif args[:2] == ['rev-parse', '--abbrev-ref']: print('main')
    elif '--git-path' in args: print(base / ('last-upload' if args[-1] == 'podhaven-last-upload' else args[-1]))
    elif args[0] == 'rev-parse':
        print('new' if args[-1] == 'HEAD' or state['tag'] != 'v1.0b568' else 'old')
    elif args[:2] == ['tag', '-l']:
        print('Generated release notes' if '--format=%(contents)' in args else state['tag'])
    elif args[:2] == ['tag', '-a']: state['tag'] = args[2]
    elif args[:2] == ['tag', '-d']: state['tag'] = 'v1.0b568'
    elif args[0] == 'ls-remote': print('remote-tag' if state['remote'] else '')
    elif args[0] == 'push': state['remote'] = True
    elif args[0] == 'diff': print('+Fixed playback')
    else: raise SystemExit('Unexpected git arguments: ' + repr(args))
    state_path.write_text(json.dumps(state))
elif name == 'xcodebuild':
    if '-showdestinations' in args: print('{ platform:iOS Simulator, OS:26.5, name:iPhone 17 }')
    elif '-showBuildSettings' in args:
        project = base / 'repo/PodHaven.xcodeproj/project.pbxproj'
        version = re.search(r'MARKETING_VERSION = ([^;]+);', project.read_text())[1] if project.exists() else os.environ.get('DEPLOY_VERSION', '1.0.1')
        print('    MARKETING_VERSION = ' + version)
    elif 'archive' in args and os.environ.get('UNAPPROVED_MACROS') and '-skipMacroValidation' not in args:
        print('error: Macro must be enabled before it can be used', file=sys.stderr)
        sys.exit(65)
    elif '-exportArchive' in args and os.environ.get('FAIL_UPLOAD'): sys.exit(42)
elif name == 'test-all':
    if os.environ.get('FAIL_LOCAL_TESTS') and '--preflight' not in args: sys.exit(44)
elif name == 'llm':
    sys.stdin.read()
    print('Generated release notes')
elif name == 'xcbeautify': print(sys.stdin.read(), end='')
elif name == 'mktemp':
    if '-d' in args: print(tempfile.mkdtemp(dir=base))
    else:
        descriptor, path = tempfile.mkstemp(dir=base)
        os.close(descriptor)
        print(path)
elif name == 'fastlane':
    phase = 'preflight' if 'preflight:true' in args else 'prepare' if 'prepare:true' in args else 'distribute'
    if os.environ.get('FAIL_TESTFLIGHT') == phase:
        print('TestFlight failure: ' + phase, file=sys.stderr)
        sys.exit(43)
    version = next((value.split(':')[1] for value in args if value.startswith('version:')), '')
    if os.environ.get('REVIEW_CONFLICT') == phase and (version == '1.3.1' or os.environ.get('REVIEW_REPEAT')):
        output = os.environ.get('PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH')
        if not output: sys.exit('An active review requires a new upload; retry without --reuse')
        parts = version.split('.')
        parts[-1] = str(int(parts[-1]) + 1)
        pathlib.Path(output).write_text('.'.join(parts))
elif name in ('gh', 'rm'): pass
else: raise SystemExit('Unexpected command: ' + name)
'''


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven deploy ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        shutil.copy2(ROOT / "bin/deploy.sh", self.repo / "bin/deploy.sh")
        (self.repo / "bin/shipit").symlink_to("deploy.sh")
        gate = self.repo / "bin/test-all"
        gate.write_text(f"#!{sys.executable}\n" + FAKE)
        gate.chmod(0o755)
        self.commands = self.base / "commands"
        self.commands.mkdir()
        for command in ("git", "xcodebuild", "llm", "xcbeautify", "mktemp", "fastlane", "gh", "rm"):
            path = self.commands / command
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        (self.base / "state").write_text(json.dumps({"tag": "v1.0b568", "remote": False}))
        self.env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                    "DEPLOY_FIXTURE": str(self.base)}
        for key in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID", "PODHAVEN_TESTFLIGHT_NOTES"):
            self.env.pop(key, None)

    def run_deploy(self, *args, **env):
        return subprocess.run(["/bin/bash", str(self.repo / "bin/deploy.sh"), *args],
                              env={**self.env, **env}, text=True, capture_output=True, timeout=15)

    def events(self, command):
        return [event for line in (self.base / "events").read_text().splitlines()
                if (event := json.loads(line))[0] == command]

    def test_local_gate_failure_prevents_summary_archive_and_upload(self):
        result = self.run_deploy(FAIL_LOCAL_TESTS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events("llm"))
        self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                             for event in self.events("xcodebuild")))

    def test_without_notes_only_uploads(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.events("fastlane"))
        self.assertTrue(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_archive_supports_package_macros_without_interactive_approval(self):
        result = self.run_deploy(UNAPPROVED_MACROS="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any('archive' in event[1] for event in self.events('xcodebuild')))
        self.assertTrue(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_shipit_rejects_malformed_testflight_versions(self):
        for version in ("2.1.1.1", "2.01.1", "2.1.beta"):
            with self.subTest(version=version):
                result = self.run_deploy(DEPLOY_VERSION=version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("two dots", result.stderr)
                self.assertFalse(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_release_upload_requires_matching_zero_or_one_dot_version(self):
        result = self.run_deploy("--appstore-release", "2.1", DEPLOY_VERSION="2.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.events("fastlane"))
        for requested, actual in (("2.1.1", "2.1.1"), ("2.1", "2.2")):
            result = self.run_deploy("--appstore-release", requested, DEPLOY_VERSION=actual)
            self.assertNotEqual(result.returncode, 0)

    def test_shipit_cannot_use_the_release_upload_mode(self):
        result = subprocess.run([str(self.repo / "bin/shipit"), "--appstore-release", "2.1"],
                                env={**self.env, "DEPLOY_VERSION": "2.1"}, text=True,
                                capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)

    def test_shipit_help_has_no_external_side_effects(self):
        result = subprocess.run([str(self.repo / "bin/shipit"), "--help"],
                                env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--notes", result.stdout)
        self.assertIn("--reuse", result.stdout)
        self.assertFalse((self.base / "events").exists())

    def test_notes_distribute_the_uploaded_version_and_build(self):
        notes = 'Fixed "playback".\nKeep $HOME and `literal` text.'
        result = self.run_deploy("--notes", notes)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.events("fastlane")
        self.assertEqual(len(calls), 3)
        self.assertIn("preflight:true", calls[0][1])
        self.assertIn("prepare:true", calls[1][1])
        self.assertIn("version:1.0.1", calls[2][1])
        self.assertIn("build:569", calls[2][1])
        self.assertEqual(calls[2][2], notes)

    def test_preflight_failure_stops_before_upload(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_TESTFLIGHT="preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("TestFlight failure", result.stderr)
        self.assertFalse(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_failed_distribution_retries_without_another_upload(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_TESTFLIGHT="distribute")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0.1b569")
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        uploads = [event for event in self.events('xcodebuild') if '-exportArchive' in event[1]]
        self.assertEqual(len(uploads), 1)
        self.assertEqual(sum("--ensure" in event[1] for event in self.events("test-all")), 2)

    def test_notes_can_distribute_a_previously_completed_upload(self):
        self.assertEqual(self.run_deploy().returncode, 0)
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.events('fastlane')), 2)
        self.assertEqual(sum('-exportArchive' in event[1] for event in self.events('xcodebuild')), 1)

    def test_failed_upload_does_not_distribute(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.events('fastlane')), 2)
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0b568")

    def test_missing_or_blank_notes_are_rejected(self):
        for args in (("--notes",), ("--notes", ""), ("--notes", "  \n")):
            with self.subTest(args=args):
                result = self.run_deploy(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--notes requires", result.stderr)


class TaggedDeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven tagged deploy ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        (self.repo / "bin").mkdir(parents=True)
        shutil.copy2(ROOT / "bin/deploy.sh", self.repo / "bin/deploy.sh")
        shutil.copy2(ROOT / "bin/version", self.repo / "bin/version")
        (self.repo / "PodHaven.xcodeproj").mkdir()
        (self.repo / "PodHaven.xcodeproj/project.pbxproj").write_text("\tMARKETING_VERSION = 1.3.1;\n")
        (self.repo / "bin/testflight").symlink_to("deploy.sh")
        gate = self.repo / "bin/test-all"
        gate.write_text(f"#!{sys.executable}\n" + FAKE)
        gate.chmod(0o755)
        commands = self.base / "commands"
        commands.mkdir()
        for name in ("xcodebuild", "llm", "xcbeautify", "mktemp", "fastlane", "gh", "rm"):
            path = commands / name
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "DEPLOY_FIXTURE": str(self.base), "DEPLOY_VERSION": "1.3.1",
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        for key in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID", "PODHAVEN_TESTFLIGHT_NOTES",
                    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Deploy Test")
        self.git("config", "user.email", "deploy@example.invalid")
        self.git("add", ".")
        self.git("commit", "-m", "App Store release")
        self.git("tag", "-a", "v1.3b574", "-m", "App Store build")
        self.git("commit", "--allow-empty", "-m", "First TestFlight build")
        self.git("tag", "-a", "v1.3.1b575", "-m", "First TestFlight build")
        self.git("commit", "--allow-empty", "-m", "Latest TestFlight build")
        self.git("tag", "-a", "v1.3.1b576", "-m", "Latest TestFlight build")
        self.git("init", "--bare", str(self.base / "remote.git"))
        for name in ("origin", "sourcehut"):
            self.git("remote", "add", name, str(self.base / "remote.git"))
        self.git("push", "-u", "origin", "main", "--tags")
        self.receipt = self.repo / ".git/podhaven-last-upload"
        self.receipt.write_text("v1.3.1b576\n")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], env=self.env,
                                       stderr=subprocess.PIPE, text=True).strip()

    def run_deploy(self, *args, **env):
        return subprocess.run([str(self.repo / "bin/testflight"), *args], cwd=self.repo,
                              env={**self.env, **env}, text=True, capture_output=True, timeout=15)

    def events(self, command=None):
        path = self.base / "events"
        events = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [event for event in events if command is None or event[0] == command]

    def assert_distribution(self, version="1.3.1", build="576"):
        calls = [event for event in self.events("fastlane") if "preflight:true" not in event[1] and "prepare:true" not in event[1]]
        self.assertEqual(len(calls), 1)
        self.assertIn("version:" + version, calls[0][1])
        self.assertIn("build:" + build, calls[0][1])
        self.assertEqual(calls[0][2], "Fixes")
        self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                             for event in self.events("xcodebuild")))

    def test_same_commit_notes_reuse_highest_build_across_version_formats(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()
        self.assertFalse(any("--ensure" in event[1] for event in self.events("test-all")))

    def test_completed_upload_without_notes_is_a_noop(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("v1.3.1b576 is already fully deployed", result.stdout)
        self.assertFalse(self.events("fastlane"))
        self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                             for event in self.events("xcodebuild")))

    def test_new_commit_upload_uses_latest_build_for_number_and_summary(self):
        (self.repo / "change.txt").write_text("New work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "New work")
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("(v1.3.1b576..HEAD)", result.stdout)
        self.assertEqual(self.receipt.read_text().strip(), "v1.3.1b577")
        self.assertTrue(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))

    def assert_review_conflict_advances_patch(self, phase):
        if phase != "preflight":
            (self.repo / "change.txt").write_text("New work")
            self.git("add", "change.txt")
            self.git("commit", "-m", "New work")
        notes = 'Fix "playback"\nKeep $HOME and `literal` text.'
        result = self.run_deploy("--notes", notes, REVIEW_CONFLICT=phase)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        expected_build = "578" if phase == "distribute" else "577"
        self.assertEqual(self.receipt.read_text().strip(), "v1.3.2b" + expected_build)
        self.assertIn("MARKETING_VERSION = 1.3.2;", (self.repo / "PodHaven.xcodeproj/project.pbxproj").read_text())
        self.assertEqual(self.git("log", "-1", "--format=%s"), "Change version number to 1.3.2")
        uploads = [event for event in self.events("xcodebuild") if "-exportArchive" in event[1]]
        self.assertEqual(len(uploads), 2 if phase == "distribute" else 1)
        calls = self.events("fastlane")
        self.assertTrue(all(event[2] == notes for event in calls))
        self.assertIn("version:1.3.2", calls[-1][1])
        self.assertIn("build:" + expected_build, calls[-1][1])
        self.assertTrue(any("--ensure" in event[1] for event in self.events("test-all")))
        self.assertEqual(self.git("status", "--porcelain"), "")
        if phase == "distribute":
            self.assertIn("v1.3.1b577", self.git("tag", "-l"))

    def test_active_review_before_upload_advances_patch(self):
        self.assert_review_conflict_advances_patch("preflight")

    def test_review_starting_during_cancellation_advances_patch(self):
        self.assert_review_conflict_advances_patch("prepare")

    def test_review_starting_after_upload_uses_another_build_number(self):
        self.assert_review_conflict_advances_patch("distribute")

    def test_cancellation_preparation_precedes_archive(self):
        (self.repo / "change.txt").write_text("New work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "New work")
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        events = self.events()
        prepare = next(i for i, event in enumerate(events) if "prepare:true" in event[1])
        archive = next(i for i, event in enumerate(events) if event[0] == "xcodebuild" and "archive" in event[1])
        self.assertLess(prepare, archive)
        self.assertTrue(any(event[0] == "test-all" and "--ensure" in event[1] for event in events[:prepare]))

    def test_patch_validation_failure_prevents_upload(self):
        result = self.run_deploy("--notes", "Fixes", REVIEW_CONFLICT="preflight", FAIL_LOCAL_TESTS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))
        self.assertEqual(self.receipt.read_text().strip(), "v1.3.1b576")

    def test_repeated_active_review_does_not_keep_bumping_versions(self):
        result = self.run_deploy("--notes", "Fixes", REVIEW_CONFLICT="preflight", REVIEW_REPEAT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already advanced", result.stderr)
        self.assertEqual(self.git("log", "-1", "--format=%s"), "Change version number to 1.3.2")
        self.assertFalse(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))

    def test_reuse_active_review_requires_a_fresh_upload(self):
        result = self.run_deploy("--reuse", "--notes", "Fixes", REVIEW_CONFLICT="distribute")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without --reuse", result.stderr)
        self.assertFalse(self.events("xcodebuild"))

    def test_reuse_after_new_commits_only_distributes(self):
        self.git("commit", "--allow-empty", "-m", "New work")
        (self.repo / ".git/podhaven-version-push").write_text("Pending version push")
        local_refs = self.git("show-ref")
        remote_refs = self.git("ls-remote", "origin")
        result = self.run_deploy("--reuse", "--notes", "Fixes", DEPLOY_VERSION="2")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()
        self.assertTrue(all(event[0] == "fastlane" for event in self.events()))
        self.assertEqual(self.git("show-ref"), local_refs)
        self.assertEqual(self.git("ls-remote", "origin"), remote_refs)
        self.assertEqual(self.receipt.read_text(), "v1.3.1b576\n")

    def test_reuse_can_verify_upload_from_remote_without_receipt(self):
        self.receipt.unlink()
        self.git("commit", "--allow-empty", "-m", "New work")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()

    def test_reuse_can_use_receipt_before_tag_publication(self):
        self.git("push", "origin", ":refs/tags/v1.3.1b576")
        self.git("commit", "--allow-empty", "-m", "New work")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()
        self.assertEqual(self.git("ls-remote", "--tags", "origin", "refs/tags/v1.3.1b576"), "")
        self.assertFalse(self.events("gh"))

    def test_reuse_ignores_newer_appstore_builds(self):
        self.git("tag", "-a", "v1.4b577", "-m", "App Store build")
        self.receipt.write_text("v1.4b577\n")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()

    def test_reuse_sorts_build_suffix_numerically(self):
        self.git("tag", "-a", "v1.3.1b999", "-m", "Older upload")
        self.git("tag", "-a", "v1.3.1b1000", "-m", "Latest upload")
        self.receipt.write_text("v1.3.1b1000\n")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution(build="1000")

    def test_reuse_without_completed_upload_stops_without_fallback(self):
        self.git("tag", "-a", "v1.3.1b577", "-m", "Not uploaded")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No completed upload", result.stderr)
        self.assertFalse(self.events())
        self.assertIn("v1.3.1b577", self.git("tag", "-l"))

    def test_reuse_rejects_a_tag_that_differs_from_the_published_tag(self):
        self.receipt.unlink()
        self.git("tag", "-f", "-a", "v1.3.1b576", "HEAD^", "-m", "Different tag")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No completed upload", result.stderr)
        self.assertFalse(self.events())

    def test_reuse_requires_force_on_another_branch(self):
        self.git("checkout", "-b", "feature")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Not on main branch", result.stderr)
        self.assertFalse(self.events())
        result = self.run_deploy("--reuse", "--notes", "Fixes", "--force")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()

    def test_reuse_rejects_a_dirty_checkout_even_with_force(self):
        (self.repo / "change.txt").write_text("Uncommitted work")
        result = self.run_deploy("--reuse", "--notes", "Fixes", "--force")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Uncommitted or untracked changes", result.stderr)
        self.assertFalse(self.events())

    def test_reuse_without_testflight_tags_stops(self):
        self.git("tag", "-d", "v1.3.1b575", "v1.3.1b576")
        result = self.run_deploy("--reuse", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No TestFlight build tag", result.stderr)
        self.assertFalse(self.events())

    def test_reuse_requires_notes_and_rejects_appstore_upload_mode(self):
        for args, message in ((["--reuse"], "--reuse requires --notes"),
                              (["--reuse", "--appstore-release", "1.4"],
                               "--reuse cannot be combined with --appstore-release")):
            with self.subTest(args=args):
                result = self.run_deploy(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.events())

    def test_reuse_failure_keeps_tags_and_never_publishes(self):
        self.git("commit", "--allow-empty", "-m", "New work")
        local_refs = self.git("show-ref")
        remote_refs = self.git("ls-remote", "origin")
        result = self.run_deploy("--reuse", "--notes", "Fixes", FAIL_TESTFLIGHT="distribute")
        self.assertEqual(result.returncode, 43, result.stdout + result.stderr)
        self.assert_distribution()
        self.assertTrue(all(event[0] == "fastlane" for event in self.events()))
        self.assertEqual(self.git("show-ref"), local_refs)
        self.assertEqual(self.git("ls-remote", "origin"), remote_refs)


if __name__ == "__main__":
    unittest.main()
