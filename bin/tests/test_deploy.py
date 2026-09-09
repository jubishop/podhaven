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
import json, os, pathlib, sys
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
    elif '--git-path' in args: print(base / 'last-upload')
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
    elif '-showBuildSettings' in args: print('    MARKETING_VERSION = 1.0.1')
    elif '-exportArchive' in args and os.environ.get('FAIL_UPLOAD'): sys.exit(42)
elif name == 'llm':
    sys.stdin.read()
    print('Generated release notes')
elif name == 'xcbeautify': print(sys.stdin.read(), end='')
elif name == 'mktemp':
    path = base / 'logs'
    path.mkdir(exist_ok=True)
    print(path)
elif name == 'fastlane':
    phase = 'preflight' if 'preflight:true' in args else 'distribute'
    if os.environ.get('FAIL_TESTFLIGHT') == phase:
        print('TestFlight failure: ' + phase, file=sys.stderr)
        sys.exit(43)
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

    def test_without_notes_only_uploads(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.events("fastlane"))
        self.assertTrue(any('-exportArchive' in event[1] for event in self.events('xcodebuild')))

    def test_shipit_help_has_no_external_side_effects(self):
        result = subprocess.run([str(self.repo / "bin/shipit"), "--help"],
                                env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--notes", result.stdout)
        self.assertFalse((self.base / "events").exists())

    def test_notes_distribute_the_uploaded_version_and_build(self):
        notes = 'Fixed "playback".\nKeep $HOME and `literal` text.'
        result = self.run_deploy("--notes", notes)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.events("fastlane")
        self.assertEqual(len(calls), 2)
        self.assertIn("preflight:true", calls[0][1])
        self.assertIn("version:1.0.1", calls[1][1])
        self.assertIn("build:569", calls[1][1])
        self.assertEqual(calls[1][2], notes)

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

    def test_notes_can_distribute_a_previously_completed_upload(self):
        self.assertEqual(self.run_deploy().returncode, 0)
        result = self.run_deploy("--notes", "Fixes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.events('fastlane')), 2)
        self.assertEqual(sum('-exportArchive' in event[1] for event in self.events('xcodebuild')), 1)

    def test_failed_upload_does_not_distribute(self):
        result = self.run_deploy("--notes", "Fixes", FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.events('fastlane')), 1)
        self.assertEqual(json.loads((self.base / "state").read_text())["tag"], "v1.0b568")

    def test_missing_or_blank_notes_are_rejected(self):
        for args in (("--notes",), ("--notes", ""), ("--notes", "  \n")):
            with self.subTest(args=args):
                result = self.run_deploy(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--notes requires", result.stderr)


if __name__ == "__main__":
    unittest.main()
