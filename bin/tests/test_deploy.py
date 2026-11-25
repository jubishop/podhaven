"""Run the deploy script with fake external commands and no release side effects."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import hang_guard
import service_guard


ROOT = Path(__file__).resolve().parents[2]
DEBUG_IDS = {"PodHaven": "4CDE6829-998C-3110-98FE-ED2AF6E992C4",
             "PodHavenWidget": "139E429B-1E6B-3F4A-9C1D-2B7A3E5F6D80"}
FAKE = r'''
import json, os, pathlib, re, subprocess, sys, tempfile
base = pathlib.Path(os.environ['DEPLOY_FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (base / 'events').open('a') as log:
    log.write(json.dumps([name, args, os.environ.get('PODHAVEN_TESTFLIGHT_NOTES'),
                          os.environ.get('SENTRY_NO_CACHE')]) + '\n')
if name == 'git':
    args = args[2:] if args[:1] == ['-C'] else args
    state_path = base / 'state'
    state = json.loads(state_path.read_text())
    if args[0] == 'status': pass
    elif args[:2] == ['rev-parse', '--abbrev-ref']: print('main')
    elif '--git-common-dir' in args: print(base)
    elif '--git-path' in args: print(base / ('last-upload' if args[-1] == 'podhaven-last-upload' else args[-1]))
    elif args[0] == 'rev-parse':
        print('new' if args[-1] == 'HEAD' or state['tag'] != 'v1.0b568' else 'old')
    elif args[:2] == ['tag', '-l']:
        print(state.get('message', 'Previous notes') if '--format=%(contents)' in args else state['tag'])
    elif args[:2] == ['tag', '-a']:
        state.update(tag=args[2], message=args[args.index('-m') + 1], cleanup=args[3])
    elif args[:2] == ['tag', '-d']:
        state['tag'] = 'v1.0b568'
        state.pop('message', None)
    elif args[0] in ('fetch', 'merge-base'): pass
    elif args[0] == 'ls-remote': print('new\trefs/tags/' + state['tag'] if state['remote'] else '')
    elif args[0] == 'push':
        if os.environ.get('FAIL_TAG_PUSH'): sys.exit("error: failed to push some refs to 'origin'")
        state['remote'] = True
    elif args[:2] == ['diff', '--quiet']: sys.exit(0 if os.environ.get('NO_CHANGES') else 1)
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
    elif 'archive' in args:
        archive = pathlib.Path(args[args.index('-archivePath') + 1])
        app = archive / 'Products/Applications/PodHaven.app'
        for binary_name, debug_id in json.loads(os.environ['DEPLOY_DEBUG_IDS']).items():
            binary = (app / binary_name if binary_name == 'PodHaven'
                      else app / 'PlugIns' / (binary_name + '.appex') / binary_name)
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_text(debug_id)
        (archive / 'dSYMs').mkdir()
    elif '-exportArchive' in args and os.environ.get('FAIL_UPLOAD'): sys.exit(42)
    elif '-exportArchive' in args and os.environ.get('PROBE_EXPORT_COPY'):
        sys.exit(subprocess.run(['cp', str(base / 'source'), str(base / 'exported')]).returncode)
elif name == 'test-all':
    if os.environ.get('FAIL_LOCAL_TESTS') and '--preflight' not in args: sys.exit(44)
elif name == 'release-notes':
    if os.environ.get('FAIL_NOTES'): sys.exit('Stopped without the generated notes.')
    print('Generated tester notes')
elif name == 'llm':
    sys.stdin.read()
    print('Generated release notes')
elif name == 'xcbeautify': print(sys.stdin.read(), end='')
elif name == 'mktemp':
    if '-d' in args: print(tempfile.mkdtemp(dir=base, prefix='logs-'))
    else:
        descriptor, path = tempfile.mkstemp(dir=base)
        os.close(descriptor)
        print(path)
elif name == 'fastlane':
    phase = ('base' if 'base:true' in args else 'preflight' if 'preflight:true' in args
             else 'prepare' if 'prepare:true' in args else 'distribute')
    if os.environ.get('FAIL_TESTFLIGHT') == phase:
        print('TestFlight failure: ' + phase, file=sys.stderr)
        sys.exit(43)
    if phase == 'base':
        pathlib.Path(os.environ['PODHAVEN_TESTFLIGHT_BASE_PATH']).write_text(os.environ.get('TESTFLIGHT_BASE_BUILD', '568'))
    version = next((value.split(':')[1] for value in args if value.startswith('version:')), '')
    if args[0] == 'manage_testers':
        (base / 'testers').write_text(json.dumps({key: os.environ.get('PODHAVEN_TESTERS_' + key)
                                                  for key in ('ADD', 'REMOVE', 'LIST')}))
    if os.environ.get('REVIEW_CONFLICT') == phase and (version == '1.3.1' or os.environ.get('REVIEW_REPEAT')):
        output = os.environ.get('PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH')
        if not output: sys.exit('An active review requires a new upload; retry without --distribute-only')
        parts = version.split('.')
        parts[-1] = str(int(parts[-1]) + 1)
        pathlib.Path(output).write_text('.'.join(parts))
elif name == 'dwarfdump':
    for path in args[1:]: print('UUID: ' + pathlib.Path(path).read_text() + ' (arm64) ' + path)
elif name == 'sentry':
    if args[:2] == ['auth', 'status'] and os.environ.get('FAIL_SENTRY') == 'auth': sys.exit(1)
    if args[:2] == ['release', 'set-commits'] and os.environ.get('FAIL_SENTRY') == 'commits':
        print('Sentry failure: commits', file=sys.stderr)
        sys.exit(45)
    if args[:2] == ['debug-files', 'upload']:
        if (os.environ.get('SENTRY_ORG'), os.environ.get('SENTRY_PROJECT')) != ('artisanal-software', 'podhaven'):
            sys.exit('Sentry debug files need the PodHaven project')
        if os.environ.get('FAIL_SENTRY') == 'debug-files':
            print('Sentry failure: debug files', file=sys.stderr)
            sys.exit(46)
    if args[:1] == ['api']:
        endpoint, debug_id = args[1].split('?query=')
        if endpoint != 'projects/artisanal-software/podhaven/files/dsyms/': sys.exit('Unexpected endpoint')
        cache_path = base / 'sentry-response-cache'
        cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
        cached = os.environ.get('SENTRY_NO_CACHE') != '1'
        if cached and args[1] in cache:
            print(cache[args[1]])
            sys.exit()
        dwarf = debug_id.upper() != os.environ.get('SENTRY_EXE_ONLY')
        body = json.dumps([{'debugId': debug_id.lower(),
                            'data': {'type': 'dbg' if dwarf else 'exe',
                                     'features': ['symtab', 'unwind'] + (['debug'] if dwarf else [])}}])
        if cached: cache_path.write_text(json.dumps({**cache, args[1]: body}))
        print(body)
elif name == 'gh':
    releases_path = base / 'releases'
    releases = json.loads(releases_path.read_text()) if releases_path.exists() else []
    if args[:2] == ['release', 'view'] and args[2] not in releases: sys.exit('release not found')
    if args[:2] == ['release', 'create']:
        if os.environ.get('FAIL_RELEASE'): sys.exit('HTTP 422: Validation Failed')
        releases_path.write_text(json.dumps(releases + [args[2]]))
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
        shutil.copy2(ROOT / "bin/_release_lock.py", self.repo / "bin/_release_lock.py")
        (self.repo / "bin/shipit").symlink_to("deploy.sh")
        for name in ("test-all", "release-notes"):
            gate = self.repo / "bin" / name
            gate.write_text(f"#!{sys.executable}\n" + FAKE)
            gate.chmod(0o755)
        self.commands = self.base / "commands"
        self.commands.mkdir()
        for command in ("git", "xcodebuild", "llm", "xcbeautify", "mktemp", "fastlane", "gh", "sentry", "dwarfdump"):
            path = self.commands / command
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        (self.base / "state").write_text(json.dumps({"tag": "v1.0b568", "remote": False}))
        self.home = self.base / "home"
        self.home.mkdir()
        self.env = {**os.environ, "PATH": str(self.commands) + os.pathsep + os.environ["PATH"],
                    "DEPLOY_FIXTURE": str(self.base), "DEPLOY_DEBUG_IDS": json.dumps(DEBUG_IDS), "HOME": str(self.home)}
        for key in ("PODHAVEN_TESTFLIGHT_NOTES", "PODHAVEN_APPSTORE_NOTES", "SENTRY_ORG", "SENTRY_PROJECT",
                    "SENTRY_NO_CACHE", "PODHAVEN_RELEASE_LOCK_FD", "PODHAVEN_RELEASE_LOCK_PID"):
            self.env.pop(key, None)
        (self.base / "AuthKey.p8").write_text("fake key")
        self.env.update(ASC_KEY_PATH=str(self.base / "AuthKey.p8"), ASC_KEY_ID="key", ASC_ISSUER_ID="issuer")

    def run_deploy(self, *args, **env):
        return hang_guard.run(["/bin/bash", str(self.repo / "bin/deploy.sh"), *args],
                              env={**self.env, **env}, text=True, capture_output=True)

    def state(self):
        return json.loads((self.base / "state").read_text())

    def events(self, command):
        return [event for line in (self.base / "events").read_text().splitlines()
                if (event := json.loads(line))[0] == command]

    def test_local_gate_failure_prevents_tag_archive_and_upload(self):
        result = self.run_deploy(FAIL_LOCAL_TESTS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state()["tag"], "v1.0b568")
        self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                             for event in self.events("xcodebuild")))

    def test_without_notes_generates_them_first_and_distributes(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in (self.base / "events").read_text().splitlines()]
        calls = self.events("fastlane")
        self.assertEqual(len(calls), 4)
        self.assertIn("base:true", calls[0][1])
        self.assertIn("version:1.0.1", calls[-1][1])
        self.assertIn("build:569", calls[-1][1])
        self.assertTrue(all(call[2] == "Generated tester notes" for call in calls[1:]))
        notes = [index for index, event in enumerate(events) if event[0] == "release-notes"]
        self.assertEqual([events[index][1] for index in notes], [["testflight", "--since-build", "568", "--to", "HEAD"]])
        first_validation = next(index for index, event in enumerate(events)
                                if event[0] == "test-all" and "--ensure" in event[1])
        self.assertLess(notes[0], first_validation)

    def test_declined_or_failed_notes_stop_before_validation_or_upload(self):
        for env in ({"FAIL_NOTES": "1"}, {"FAIL_TESTFLIGHT": "base"}):
            with self.subTest(failure=next(iter(env))):
                self.setUp()
                result = self.run_deploy(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any("--ensure" in event[1] for event in self.events("test-all")))
                self.assertFalse(any("archive" in event[1] for event in self.events("xcodebuild")))
                self.assertEqual(len(self.events("fastlane")), 1)
                self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0b568")

    def test_a_missing_fake_never_runs_the_live_command(self):
        for name in ("fastlane", "gh", "sentry", "xcodebuild"):
            with self.subTest(command=name):
                self.setUp()
                (self.commands / name).unlink()
                self.run_deploy("--notes", "Fixes")
                self.assertIn(name, [call.split()[0] for call in service_guard.take_blocked()])

    def test_successful_upload_pushes_only_its_tag_to_origin(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        pushes = [event[1][2:] for event in self.events("git") if event[1][2:3] == ["push"]]
        self.assertEqual(pushes, [["push", "origin", "v1.0.1b569"]])

    def test_failed_publication_stops_before_distribution_with_a_working_retry_command(self):
        for failure, error, message in (
                ("FAIL_TAG_PUSH", "failed to push some refs", "Could not push v1.0.1b569 to origin"),
                ("FAIL_RELEASE", "HTTP 422", "Could not create the v1.0.1b569 GitHub release")):
            with self.subTest(failure=failure):
                self.setUp()
                result = self.run_deploy("--notes", "Fixed playback", **{failure: "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(error, result.stderr)
                self.assertIn(message, result.stderr)
                self.assertEqual([call[1][1] for call in self.events("fastlane")], ["preflight:true", "prepare:true"])
                retry = next(line.split("Retry with: ", 1)[1] for line in result.stderr.splitlines()
                             if "Retry with: " in line)
                result = hang_guard.run(["/bin/bash", "-c", retry], env=self.env, text=True,
                                        capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
                self.assertTrue(json.loads((self.base / "state").read_text())["remote"])
                self.assertEqual(json.loads((self.base / "releases").read_text()), ["v1.0.1b569"])
                creates = [event[1] for event in self.events("gh") if event[1][:2] == ["release", "create"]]
                self.assertTrue(all(args[2:4] == ["v1.0.1b569", "--verify-tag"] for args in creates))
                distribution = self.events("fastlane")[-1]
                self.assertEqual(distribution[1][1:], ["version:1.0.1", "build:569"])
                self.assertEqual(distribution[2], "Fixed playback")

    def test_upload_keeps_the_newest_three_release_folders(self):
        organizer = self.home / "Library/Developer/Xcode/Archives/2026-11-08/PodHaven 11-8-26, 9.00 PM.xcarchive"
        organizer.mkdir(parents=True)
        releases = self.repo / "build/release"
        for name in ("v1.0b9", "v1.0b566", "v0.9b567", "v1.0b568", "notes"):
            (releases / name).mkdir(parents=True)
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(organizer.is_dir())
        self.assertEqual(sorted(path.name for path in releases.iterdir()),
                         ["notes", "v0.9b567", "v1.0.1b569", "v1.0b568"])
        self.assertIn("Removed the output of v1.0b9, v1.0b566;", result.stdout)
        self.assertTrue((releases / "v1.0.1b569/PodHaven.xcarchive/Products/Applications/PodHaven.app").is_dir())
        self.assertTrue((releases / "v1.0.1b569/xcodebuild-archive.log").is_file())
        self.assertTrue((releases / "v1.0.1b569/xcodebuild-upload.log").is_file())
        self.assertFalse(list(self.base.glob("logs-*")))

    def test_failed_upload_keeps_its_logs_and_a_retry_archives_again(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        folder = self.repo / "build/release/v1.0.1b569"
        self.assertIn("All logs and artifacts: " + str(folder), result.stderr)
        self.assertTrue((folder / "xcodebuild-upload.log").is_file())
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sum("archive" in event[1] for event in self.events("xcodebuild")), 2)

    def test_the_repository_ignores_release_folders(self):
        result = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--quiet", "--no-index",
                                 "build/release/v1.0.1b569/PodHaven.xcarchive"])
        self.assertEqual(result.returncode, 0)

    def test_archive_supports_package_macros_without_interactive_approval(self):
        result = self.run_deploy(UNAPPROVED_MACROS="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any('archive' in event[1] for event in self.events('xcodebuild')))
        self.assertTrue(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_export_uses_system_copy_tools_when_path_contains_incompatible_tools(self):
        shadow = self.commands / "cp"
        shadow.write_text("#!/bin/sh\necho 'incompatible copy tool' >&2\nexit 70\n")
        shadow.chmod(0o755)
        (self.base / "source").write_text("exported app symbols")

        result = self.run_deploy("--notes", "Fixes", PROBE_EXPORT_COPY="1")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.base / "exported").read_text(), "exported app symbols")
        self.assertEqual(len(self.events("fastlane")), 3)
        self.assertEqual(len(self.events("xcbeautify")), 2)
        self.assertTrue(self.events("gh"))
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0.1b569")

    def test_shipit_rejects_malformed_testflight_versions(self):
        for version in ("2.1.1.1", "2.01.1", "2.1.beta"):
            with self.subTest(version=version):
                self.setUp()
                result = self.run_deploy(DEPLOY_VERSION=version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("two dots", result.stderr)
                self.assertFalse(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))
                self.assertFalse(self.events("fastlane"))

    def test_release_upload_requires_matching_zero_or_one_dot_version(self):
        result = self.run_deploy("--appstore-release", "2.1", DEPLOY_VERSION="2.1", PODHAVEN_APPSTORE_NOTES="Public notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.events("fastlane"))
        self.assertEqual(self.state()["message"], "Public notes")
        for requested, actual in (("2.1.1", "2.1.1"), ("2.1", "2.2")):
            result = self.run_deploy("--appstore-release", requested, DEPLOY_VERSION=actual,
                                     PODHAVEN_APPSTORE_NOTES="Public notes")
            self.assertNotEqual(result.returncode, 0)

    def test_release_upload_needs_the_app_store_notes(self):
        for notes in ("", " \n"):
            with self.subTest(notes=notes):
                self.setUp()
                result = self.run_deploy("--appstore-release", "2.1", DEPLOY_VERSION="2.1", PODHAVEN_APPSTORE_NOTES=notes)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("run bin/appstore instead", result.stderr)
                self.assertFalse((self.base / "events").exists())

    def test_shipit_cannot_use_the_release_upload_mode(self):
        result = hang_guard.run([str(self.repo / "bin/shipit"), "--appstore-release", "2.1"],
                                env={**self.env, "DEPLOY_VERSION": "2.1"}, text=True,
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_shipit_help_has_no_external_side_effects(self):
        result = hang_guard.run([str(self.repo / "bin/shipit"), "--help"],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in ("--notes", "--distribute-only", "--reuse is an alias", "--add-tester", "--remove-tester",
                       "--testers", "PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS", "build/release/<tag>"):
            self.assertIn(option, result.stdout)
        self.assertNotIn("Apple ID login;", result.stdout)
        self.assertFalse((self.base / "events").exists())

    def test_every_release_needs_the_api_key(self):
        for missing in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"):
            for args in ((), ("--notes", "Fixes"), ("--distribute-only",), ("--testers",)):
                with self.subTest(missing=missing, args=args):
                    self.setUp()
                    result = self.run_deploy(*args, **{missing: ""})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("need an API key", result.stderr)
                    self.assertFalse((self.base / "events").exists())
        self.setUp()
        result = self.run_deploy("--notes", "Fixes", ASC_KEY_PATH=str(self.base / "missing.p8"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("API key not found", result.stderr)
        self.assertFalse((self.base / "events").exists())

    def test_uploads_and_distribution_use_the_api_key(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for event in self.events("xcodebuild"):
            if "archive" in event[1] or "-exportArchive" in event[1]:
                key = event[1].index("-authenticationKeyPath")
                self.assertEqual(event[1][key:key + 6], ["-authenticationKeyPath", str(self.base / "AuthKey.p8"),
                                                         "-authenticationKeyID", "key",
                                                         "-authenticationKeyIssuerID", "issuer"])

    def test_the_new_tag_message_is_the_notes(self):
        notes = "# Fixed playback\nKeep $HOME and `literal` text.  "
        result = self.run_deploy("--notes", notes)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()["message"], notes)
        self.assertEqual(self.state()["cleanup"], "--cleanup=verbatim")
        creates = [event[1] for event in self.events("gh") if event[1][:2] == ["release", "create"]]
        self.assertEqual(creates[0][-2:], ["--notes", notes])
        self.assertFalse(self.events("llm"))

    def test_generated_notes_are_the_new_tag_message(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.state()["message"], "Generated tester notes")
        self.assertFalse(self.events("llm"))

    def test_an_unchanged_tree_is_not_uploaded_again(self):
        result = self.run_deploy("--notes", "Fixes", NO_CHANGES="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No changes to deploy since v1.0b568", result.stderr)
        self.assertEqual(self.state()["tag"], "v1.0b568")
        self.assertFalse(any("archive" in event[1] for event in self.events("xcodebuild")))

    def test_another_release_holding_the_lock_stops_the_command(self):
        with (self.base / "podhaven-release.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock.write("pid 1 since 2026-11-24 09:00:00 PST: bin/appstore in /elsewhere\n")
            lock.flush()
            result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Another release command holds", result.stderr)
        self.assertIn("bin/appstore in /elsewhere", result.stderr)
        self.assertEqual([event[1][2:] for event in self.events("git")],
                         [["rev-parse", "--path-format=absolute", "--git-common-dir"]])
        self.assertFalse(self.events("fastlane"))
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("bin/deploy.sh in " + str(self.repo), (self.base / "podhaven-release.lock").read_text())

    def test_tester_options_manage_everyone_without_git_or_the_lock(self):
        with (self.base / "podhaven-release.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_deploy("--add-tester", " Friend@Example.COM ", "--add-tester", "friend@example.com",
                                     "--remove-tester", "old@example.com", "--add-tester", "new+tag@example.org",
                                     "--testers")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([event[1] for event in self.events("fastlane")], [["manage_testers"]])
        self.assertEqual(json.loads((self.base / "testers").read_text()),
                         {"ADD": "friend@example.com\nnew+tag@example.org\n", "REMOVE": "old@example.com\n",
                          "LIST": "true"})
        self.assertFalse(self.events("git"))
        for args in (("--testers",), ("--remove-tester", "old@example.com")):
            with self.subTest(args=args):
                self.setUp()
                result = self.run_deploy(*args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual([json.loads(line)[0] for line in (self.base / "events").read_text().splitlines()],
                                 ["fastlane"])

    def test_bad_tester_options_stop_before_apple(self):
        for args, message in (
                (("--add-tester",), "needs an email address"),
                (("--add-tester", "friend"), 'not "friend"'),
                (("--remove-tester", "friend@example"), "needs an email address"),
                (("--add-tester", "two words@example.com"), "needs an email address"),
                (("--add-tester", "a@example.com", "--remove-tester", "A@example.com"), "Both --add-tester"),
                (("--testers", "--notes", "Fixes"), "without a release"),
                (("--testers", "--distribute-only"), "without a release"),
                (("--add-tester", "a@example.com", "--reuse"), "without a release"),
                (("--testers", "-f"), "without a release")):
            with self.subTest(args=args):
                self.setUp()
                result = self.run_deploy(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
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

    def test_upload_associates_release_commits_before_distribution(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        release = "artisanal-software/com.artisanalsoftware.PodHaven@1.0.1+569"
        self.assertEqual([event[1] for event in self.events("sentry") if event[1][0] in ("auth", "release")], [
            ["auth", "status"],
            ["release", "create", release, "--project", "podhaven"],
            ["release", "set-commits", release, "--from", "v1.0b568"],
        ])
        order = [(event[0], event[1]) for line in (self.base / "events").read_text().splitlines()
                 if (event := json.loads(line))[0] in ("xcodebuild", "sentry", "fastlane")]
        upload = next(index for index, (name, args) in enumerate(order) if "-exportArchive" in args)
        commits = order.index(("sentry", ["release", "set-commits", release, "--from", "v1.0b568"]))
        distribution = max(index for index, (name, args) in enumerate(order)
                           if name == "fastlane" and "preflight:true" not in args and "prepare:true" not in args)
        self.assertLess(upload, commits)
        self.assertLess(commits, distribution)

    def test_sentry_auth_failure_stops_before_archive(self):
        result = self.run_deploy(FAIL_SENTRY="auth")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sentry auth login", result.stderr)
        self.assertFalse(any("archive" in event[1] for event in self.events("xcodebuild")))

    def test_failed_sentry_commits_retry_without_another_upload(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_SENTRY="commits")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Sentry release commits", result.stderr)
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0.1b569")
        self.assertFalse([event for event in self.events("fastlane")
                          if "preflight:true" not in event[1] and "prepare:true" not in event[1]])
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)
        commits = [event[1] for event in self.events("sentry") if event[1][:2] == ["release", "set-commits"]]
        self.assertEqual(len(commits), 2)
        self.assertEqual(commits[-1][2], "artisanal-software/com.artisanalsoftware.PodHaven@1.0.1+569")

    def test_archived_debug_symbols_reach_sentry_before_app_store_upload(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        order = [(event[0], event[1]) for line in (self.base / "events").read_text().splitlines()
                 if (event := json.loads(line))[0] in ("xcodebuild", "sentry")]
        archive = next(index for index, (name, args) in enumerate(order) if name == "xcodebuild" and "archive" in args)
        upload = next(index for index, (name, args) in enumerate(order) if "-exportArchive" in args)
        symbols = next(index for index, (name, args) in enumerate(order) if args[:2] == ["debug-files", "upload"])
        self.assertTrue(order[symbols][1][2].endswith("/PodHaven.xcarchive"))
        self.assertIn("--wait", order[symbols][1])
        checks = [index for index, (name, args) in enumerate(order) if args[:1] == ["api"]]
        self.assertEqual(sorted(order[index][1][1].split("=")[1] for index in checks),
                         sorted(debug_id.lower() for debug_id in DEBUG_IDS.values()))
        self.assertLess(archive, symbols)
        self.assertLess(symbols, min(checks))
        self.assertLess(max(checks), upload)

    def test_missing_dwarf_in_sentry_stops_before_app_store_upload(self):
        for name, debug_id in DEBUG_IDS.items():
            with self.subTest(binary=name):
                self.setUp()
                result = self.run_deploy("--notes", "Fixes", SENTRY_EXE_ONLY=debug_id)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(debug_id.lower(), result.stderr)
                self.assertIn("Sentry debug symbols", result.stderr)
                self.assertFalse(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))
                self.assertEqual(len(self.events("fastlane")), 2)
                self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0b568")

    def test_rerun_reads_debug_files_sentry_gained_after_a_failed_check(self):
        result = self.run_deploy("--notes", "Fixes", SENTRY_EXE_ONLY=DEBUG_IDS["PodHaven"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Sentry debug symbols", result.stderr)
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(sum("-exportArchive" in event[1] for event in self.events("xcodebuild")), 1)

    def test_every_sentry_call_bypasses_the_cli_response_cache(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.events("sentry")
        self.assertEqual({tuple(call[1][:1]) for call in calls},
                         {("auth",), ("debug-files",), ("api",), ("release",)})
        self.assertEqual([call[1] for call in calls if call[3] != "1"], [])

    def test_failed_debug_symbol_upload_stops_before_app_store_upload(self):
        result = self.run_deploy(FAIL_SENTRY="debug-files")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Sentry failure: debug files", result.stderr)
        self.assertFalse(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))

    def test_retry_distributes_with_the_tag_notes_without_another_upload(self):
        result = self.run_deploy(FAIL_TESTFLIGHT="distribute")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("v1.0.1b569 was uploaded. Retry with: ", result.stderr)
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Notes from v1.0.1b569:\n\nGenerated tester notes", result.stdout)
        self.assertEqual(sum('-exportArchive' in event[1] for event in self.events('xcodebuild')), 1)
        self.assertEqual([event[1][2] for event in self.events("release-notes")], ["568"])
        self.assertEqual(self.events("fastlane")[-1][2], "Generated tester notes")

    def test_failed_upload_does_not_distribute(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.events('fastlane')), 2)
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0b568")

    def test_missing_or_blank_notes_are_rejected(self):
        for args in (("--notes",), ("--notes", ""), ("--notes", "  \n")):
            with self.subTest(args=args):
                self.setUp()
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
        for name in ("deploy.sh", "_release_lock.py", "version", "release-notes"):
            shutil.copy2(ROOT / "bin" / name, self.repo / "bin" / name)
        (self.repo / ".gitignore").write_text("build/\n")
        (self.repo / "PodHaven.xcodeproj").mkdir()
        (self.repo / "PodHaven.xcodeproj/project.pbxproj").write_text("\tMARKETING_VERSION = 1.3.1;\n")
        (self.repo / "bin/testflight").symlink_to("deploy.sh")
        gate = self.repo / "bin/test-all"
        gate.write_text(f"#!{sys.executable}\n" + FAKE)
        gate.chmod(0o755)
        self.commands = commands = self.base / "commands"
        commands.mkdir()
        for name in ("xcodebuild", "llm", "xcbeautify", "mktemp", "fastlane", "gh", "sentry", "dwarfdump"):
            path = commands / name
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        (self.base / "AuthKey.p8").write_text("fake key")
        self.env = {**os.environ, "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                    "ASC_KEY_PATH": str(self.base / "AuthKey.p8"), "ASC_KEY_ID": "key", "ASC_ISSUER_ID": "issuer",
                    "DEPLOY_FIXTURE": str(self.base), "DEPLOY_VERSION": "1.3.1", "TESTFLIGHT_BASE_BUILD": "575",
                    "DEPLOY_DEBUG_IDS": json.dumps(DEBUG_IDS), "HOME": str(self.base),
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
        for key in ("PODHAVEN_TESTFLIGHT_NOTES", "SENTRY_ORG", "SENTRY_PROJECT", "SENTRY_NO_CACHE", "GIT_DIR",
                    "GIT_WORK_TREE", "GIT_INDEX_FILE", "PODHAVEN_RELEASE_LOCK_FD", "PODHAVEN_RELEASE_LOCK_PID"):
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
        self.git("remote", "add", "origin", str(self.base / "remote.git"))
        self.git("push", "-u", "origin", "main", "--tags")
        self.receipt = self.repo / ".git/podhaven-last-upload"
        self.receipt.write_text("v1.3.1b576\n")
        (self.base / "releases").write_text(json.dumps(["v1.3b574", "v1.3.1b575", "v1.3.1b576"]))

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], env=self.env,
                                       stderr=subprocess.PIPE, text=True).strip()

    def run_deploy(self, *args, **env):
        return hang_guard.run([str(self.repo / "bin/testflight"), *args], cwd=self.repo,
                              env={**self.env, **env}, text=True, capture_output=True)

    def events(self, command=None):
        path = self.base / "events"
        events = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [event for event in events if command is None or event[0] == command]

    def assert_distribution(self, version="1.3.1", build="576", notes="Fixes"):
        calls = [event for event in self.events("fastlane")
                 if not {"base:true", "preflight:true", "prepare:true"} & set(event[1])]
        self.assertEqual(len(calls), 1)
        self.assertIn("version:" + version, calls[0][1])
        self.assertIn("build:" + build, calls[0][1])
        self.assertEqual(calls[0][2], notes)
        self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                             for event in self.events("xcodebuild")))

    def test_same_commit_notes_reuse_highest_build_across_version_formats(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()
        self.assertFalse(any("--ensure" in event[1] for event in self.events("test-all")))

    def test_build_already_in_testing_needs_no_notes_or_distribution(self):
        for args in ((), ("--distribute-only",), ("--reuse",)):
            with self.subTest(args=args):
                self.setUp()
                result = self.run_deploy(*args, TESTFLIGHT_BASE_BUILD="576")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("576 is already in testing for Everyone", result.stdout)
                self.assertEqual([event[1][1] for event in self.events("fastlane")], ["base:true"])
                self.assertFalse(self.events("llm"))
                self.assertFalse(any("archive" in event[1] or "-exportArchive" in event[1]
                                     for event in self.events("xcodebuild")))

    def test_build_already_in_testing_publishes_its_missing_tag_and_release(self):
        self.git("push", "origin", ":refs/tags/v1.3.1b576")
        (self.base / "releases").write_text(json.dumps(["v1.3b574", "v1.3.1b575"]))
        result = self.run_deploy("--reuse", TESTFLIGHT_BASE_BUILD="576")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("ls-remote", "--tags", "origin", "refs/tags/v1.3.1b576"), "")
        self.assertFalse(self.events("gh"))
        result = self.run_deploy(TESTFLIGHT_BASE_BUILD="576", FAIL_RELEASE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP 422", result.stderr)
        self.assertIn("Could not create the v1.3.1b576 GitHub release", result.stderr)
        retry = next(line.split("Retry with: ", 1)[1] for line in result.stderr.splitlines() if "Retry with: " in line)
        result = hang_guard.run(["/bin/bash", "-c", retry], cwd=self.repo, env={**self.env, "TESTFLIGHT_BASE_BUILD": "576"},
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("576 is already in testing for Everyone", result.stdout)
        self.assertEqual(self.git("ls-remote", "--tags", "origin", "refs/tags/v1.3.1b576"),
                         self.git("rev-parse", "refs/tags/v1.3.1b576") + "\trefs/tags/v1.3.1b576")
        self.assertEqual([event[1] for event in self.events("gh") if event[1][:2] == ["release", "create"]][-1],
                         ["release", "create", "v1.3.1b576", "--verify-tag", "--title", "v1.3.1b576",
                          "--notes", "Latest TestFlight build"])
        self.assertEqual(json.loads((self.base / "releases").read_text())[-1], "v1.3.1b576")
        self.assertEqual([event[1][1] for event in self.events("fastlane")], ["base:true"] * 3)

    def test_unpushed_head_stops_before_notes_or_archive(self):
        (self.repo / "change.txt").write_text("Local work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "Local work")
        tags = self.git("tag", "-l")
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not on origin/main", result.stderr)
        self.assertIn("git push origin HEAD:main", result.stderr)
        self.assertFalse(self.events("fastlane"))
        self.assertFalse(any("archive" in event[1] for event in self.events("xcodebuild")))
        self.assertEqual(self.git("tag", "-l"), tags)
        self.git("push", "origin", "HEAD:main")
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("ls-remote", "--tags", "origin", "refs/tags/v1.3.1b577"),
                         self.git("rev-parse", "refs/tags/v1.3.1b577") + "\trefs/tags/v1.3.1b577")

    def test_forced_branch_must_be_on_its_origin_branch(self):
        self.git("checkout", "-b", "feature")
        (self.repo / "change.txt").write_text("Feature work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "Feature work")
        result = self.run_deploy("--force", "--notes", "Fixes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not fetch origin/feature", result.stderr)
        self.assertIn("git push origin HEAD:feature", result.stderr)
        self.assertFalse(self.events("fastlane"))
        self.git("push", "-u", "origin", "feature")
        result = self.run_deploy("--force", "--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("refs/tags/v1.3.1b577", self.git("ls-remote", "--tags", "origin"))

    def test_without_notes_distributes_a_completed_upload_with_its_tag_notes(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Notes from v1.3.1b576:\n\nLatest TestFlight build", result.stdout)
        self.assert_distribution(notes="Latest TestFlight build")
        self.assertFalse(any("--ensure" in event[1] for event in self.events("test-all")))
        self.assertFalse(self.events("llm"))

    def test_distribute_only_without_notes_uses_the_tag_notes(self):
        (self.repo / "PodHaven").mkdir()
        (self.repo / "PodHaven/Later.swift").write_text("New work")
        self.git("add", ".")
        self.git("commit", "-m", "Later app work")
        result = self.run_deploy("--distribute-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Distributing v1.3.1b576", result.stdout)
        self.assert_distribution(notes="Latest TestFlight build")
        self.assertFalse(self.events("llm"))

    def test_distribution_and_given_notes_need_no_llm(self):
        (self.commands / "llm").unlink()
        environment = {**self.env, "PATH": str(self.commands) + ":/usr/bin:/bin:/usr/sbin:/sbin"}
        for args in (("--distribute-only",), ("--reuse", "--notes", "Fixes"), ()):
            with self.subTest(args=args):
                result = hang_guard.run([str(self.repo / "bin/testflight"), *args], cwd=self.repo, env=environment,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.repo / "change.txt").write_text("New work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "New work")
        self.git("push")
        result = hang_guard.run([str(self.repo / "bin/testflight"), "--notes", "Fixes"], cwd=self.repo,
                                env=environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("tag", "-l", "--format=%(contents)", "v1.3.1b577"), "Fixes")

    def test_unknown_or_missing_tested_build_stops_before_version_changes(self):
        for tested in ("999", ""):
            with self.subTest(tested=tested):
                self.setUp()
                self.project_version("1.4")
                head = self.git("rev-parse", "HEAD")
                result = self.run_deploy(DEPLOY_VERSION="1.4", TESTFLIGHT_BASE_BUILD=tested)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--notes", result.stderr)
                self.assertEqual(self.git("rev-parse", "HEAD"), head)
                self.assertFalse(any("archive" in event[1] for event in self.events("xcodebuild")))

    def project_version(self, version):
        (self.repo / "PodHaven.xcodeproj/project.pbxproj").write_text(f"\tMARKETING_VERSION = {version};\n")
        self.git("commit", "-am", "Change version number to " + version)
        self.git("push")

    def test_patch_retry_keeps_the_generated_notes(self):
        (self.repo / "PodHaven").mkdir()
        (self.repo / "PodHaven/Player.swift").write_text("Fix CarPlay skipping")
        self.git("add", ".")
        self.git("commit", "-m", "Fix CarPlay skipping")
        self.git("push")
        result = self.run_deploy(REVIEW_CONFLICT="preflight")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.receipt.read_text().strip(), "v1.3.2b577")
        calls = self.events("fastlane")
        self.assertEqual(sum("base:true" in call[1] for call in calls), 1)
        self.assertTrue(all(call[2] == "Generated release notes" for call in calls[1:]))
        self.assertIn("version:1.3.2", calls[-1][1])

    def test_new_commit_upload_uses_latest_build_for_number_and_summary(self):
        (self.repo / "change.txt").write_text("New work")
        self.git("add", "change.txt")
        self.git("commit", "-m", "New work")
        self.git("push")
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("(v1.3.1b576..HEAD)", result.stdout)
        self.assertEqual(self.receipt.read_text().strip(), "v1.3.1b577")
        self.assertEqual(self.git("tag", "-l", "--format=%(contents)", "v1.3.1b577"),
                         "Behind-the-scenes stability and performance improvements.")
        self.assertTrue(any("-exportArchive" in event[1] for event in self.events("xcodebuild")))
        self.assertIn(["release", "set-commits", "artisanal-software/com.artisanalsoftware.PodHaven@1.3.1+577",
                       "--from", "v1.3.1b576"], [event[1] for event in self.events("sentry")])

    def test_reused_upload_associates_commits_since_the_previous_tag(self):
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(["release", "set-commits", "artisanal-software/com.artisanalsoftware.PodHaven@1.3.1+576",
                       "--from", "v1.3.1b575"], [event[1] for event in self.events("sentry")])

    def assert_review_conflict_advances_patch(self, phase):
        if phase != "preflight":
            (self.repo / "change.txt").write_text("New work")
            self.git("add", "change.txt")
            self.git("commit", "-m", "New work")
            self.git("push")
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
        kept = {"preflight": ["v1.3.2b577"], "prepare": ["v1.3.2b577"], "distribute": ["v1.3.1b577", "v1.3.2b578"]}
        self.assertEqual(sorted(path.name for path in (self.repo / "build/release").iterdir()), kept[phase])
        published = self.git("ls-remote", "--tags", "origin")
        self.assertIn("refs/tags/v1.3.2b" + expected_build, published)
        if phase == "distribute":
            self.assertIn("v1.3.1b577", self.git("tag", "-l"))
            self.assertIn("refs/tags/v1.3.1b577", published)

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
        self.git("push")
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
        self.assertIn("without --distribute-only", result.stderr)
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

    def test_reuse_rejects_appstore_upload_mode(self):
        for flag in ("--distribute-only", "--reuse"):
            with self.subTest(flag=flag):
                result = self.run_deploy(flag, "--appstore-release", "1.4")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--distribute-only cannot be combined with --appstore-release", result.stderr)
                self.assertFalse(self.events())

    def test_a_release_from_another_checkout_of_the_clone_holds_the_lock(self):
        worktree = self.base / "other checkout"
        self.git("worktree", "add", "--detach", str(worktree))
        with (self.repo / ".git/podhaven-release.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock.write("pid 1 since 2026-11-24 09:00:00 PST: bin/testflight in elsewhere\n")
            lock.flush()
            for folder in (self.repo, worktree):
                for args in (("--notes", "Fixes"), ("--distribute-only",)):
                    with self.subTest(folder=folder.name, args=args):
                        result = hang_guard.run([str(folder / "bin/testflight"), *args], cwd=folder, env=self.env,
                                                text=True, capture_output=True)
                        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                        self.assertIn("bin/testflight in elsewhere", result.stderr)
                        self.assertFalse(self.events())
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_distribution()

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
