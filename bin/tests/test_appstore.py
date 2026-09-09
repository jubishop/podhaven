"""Exercise the App Store command with a fake Fastlane executable."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AppStoreCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven appstore ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        (self.base / "bin").mkdir()
        self.command = self.base / "bin/appstore"
        if (ROOT / "bin/appstore").exists():
            shutil.copy2(ROOT / "bin/appstore", self.command)
        version = self.base / "bin/version"
        version.write_text('#!/bin/sh\nprintf "1.0.1\\n"\n')
        version.chmod(0o755)
        fastlane = self.base / "bin/fastlane"
        fastlane.write_text(f'#!{sys.executable}\n' + '''
import json, os, sys
from pathlib import Path
Path(os.environ['APPSTORE_EVENTS']).write_text(json.dumps({
    'args': sys.argv[1:], 'notes': os.environ.get('PODHAVEN_APPSTORE_NOTES'),
    'key_path': os.environ.get('ASC_KEY_PATH'), 'cwd': os.getcwd()
}))
sys.exit(int(os.environ.get('APPSTORE_EXIT', '0')))
''')
        fastlane.chmod(0o755)
        self.events = self.base / "events.json"
        self.env = {**os.environ, "PATH": str(self.base / "bin") + os.pathsep + os.environ["PATH"],
                    "APPSTORE_EVENTS": str(self.events)}
        for key in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID", "PODHAVEN_APPSTORE_NOTES"):
            self.env.pop(key, None)

    def run_command(self, *args, **env):
        return subprocess.run([sys.executable, str(self.command), *args], cwd=self.temp.name,
                              env={**self.env, **env}, text=True, capture_output=True, timeout=10)

    def test_default_is_read_only_status_for_current_version(self):
        result = self.run_command(PODHAVEN_APPSTORE_NOTES="stale inherited text")
        self.assertEqual(result.returncode, 0, result.stderr)
        event = json.loads(self.events.read_text())
        self.assertEqual(event["args"], ["manage_appstore", "mode:status", "version:1.0.1"])
        self.assertIsNone(event["notes"])

    def test_notes_submit_with_optional_exact_build(self):
        notes = 'Fixed "playback".\nLiteral $HOME and `text`.'
        result = self.run_command("--notes", notes, "--build", "569")
        self.assertEqual(result.returncode, 0, result.stderr)
        event = json.loads(self.events.read_text())
        self.assertEqual(event["args"], ["manage_appstore", "mode:submit", "version:1.0.1", "build:569"])
        self.assertEqual(event["notes"], notes)
        self.assertEqual(Path(event["cwd"]), self.base)

    def test_bad_arguments_do_not_contact_apple(self):
        for args in (("--notes", ""), ("--notes", "   "), ("--notes", "a" * 4001),
                     ("--build", "569"), ("--notes", "Fix", "--build", "latest"),
                     ("--api-key-id", "key")):
            with self.subTest(args=args[:2]):
                result = self.run_command(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.events.exists())

    def test_help_does_not_contact_apple(self):
        result = self.run_command("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--notes", result.stdout)
        self.assertFalse(self.events.exists())

    def test_existing_api_key_flags_and_failure_exit_are_preserved(self):
        (self.base / "key.p8").write_text("fake key")
        result = self.run_command("--api-key", "key.p8", "--api-key-id", "key",
                                  "--api-issuer-id", "issuer", APPSTORE_EXIT="23")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual(json.loads(self.events.read_text())["key_path"], str(self.base / "key.p8"))


if __name__ == "__main__":
    unittest.main()
