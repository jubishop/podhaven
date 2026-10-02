from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / ".agents/scripts/sentry-cli/download_event_attachments.sh"
)
APP_LOG = b'{"message":"current app log"}\n'
SECOND_APP_LOG = b'{"message":"second app log"}\n'
WIDGET_LOG = b'{"message":"first widget log"}\n'


class SentryAttachmentDownloadTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.calls = self.root / "calls.jsonl"
        self.issue = self.root / "issue.json"
        self.issue.write_text(json.dumps({
            "org": "artisanal-software", "project": {"slug": "podhaven"},
        }))
        self.fake = self.root / "sentry"
        self.fake.write_text('''#!/usr/bin/env python3
import json
import os
import signal
import sys

args = sys.argv[1:]
with open(os.environ["ATTACHMENT_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args == ["auth", "status"]:
    sys.exit(0)
if args[0] != "api":
    sys.exit(f"Unexpected command: {args}")
endpoint = args[1]
if endpoint.endswith("/attachments/"):
    rows = [{"id": "app", "name": "log.ndjson"}]
    if "/events/first/" in endpoint:
        rows.append({"id": "widget", "name": "widget-log.ndjson"})
    print(json.dumps({"status": 200, "body": rows}))
elif endpoint.endswith("/attachments/app/?download=1"):
    message = "second app log" if "/events/second/" in endpoint else "current app log"
    print(json.dumps({"message": message}, separators=(",", ":")))
elif endpoint.endswith("/attachments/widget/?download=1"):
    mode = os.environ["ATTACHMENT_TEST_FAILURE"]
    if mode:
        print('{"message":"interrupted', end="", flush=True)
        if mode == "signal":
            os.kill(os.getppid(), signal.SIGTERM)
        sys.exit(1)
    print('{"message":"first widget log"}')
else:
    sys.exit(f"Unexpected endpoint: {endpoint}")
''')
        self.fake.chmod(0o755)

    def download(self, output, *, event="first", failure="", selection=("--all",)):
        return subprocess.run(
            ["bash", str(SCRIPT), "--event", event, "--issue-json", str(self.issue),
             "--dir", str(output), *selection],
            capture_output=True, text=True, timeout=10, check=False,
            env={**os.environ, "SENTRY_BIN": str(self.fake),
                 "ATTACHMENT_TEST_CALLS": str(self.calls),
                 "ATTACHMENT_TEST_FAILURE": failure},
        )

    def contents(self, directory):
        return {path.name: path.read_bytes() for path in directory.iterdir()}

    def test_changed_attachment_set_requires_a_fresh_investigation(self):
        first = self.root / "cache with spaces" / "first" / "attachments"
        result = self.download(first)
        self.assertEqual(result.returncode, 0, result.stderr)
        original = {"log.ndjson": APP_LOG, "widget-log.ndjson": WIDGET_LOG}
        self.assertEqual(self.contents(first), original)
        calls = self.calls.read_bytes()

        result = self.download(first, event="second")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("fresh", result.stderr)
        self.assertEqual(self.calls.read_bytes(), calls)
        self.assertEqual(self.contents(first), original)

        second = first.parent.parent / "second" / "attachments"
        result = self.download(f"{second}///", event="second")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.contents(second), {"log.ndjson": SECOND_APP_LOG})
        self.assertEqual(self.contents(first), original)

    def test_existing_paths_are_preserved_before_network_access(self):
        unrelated = self.root / "unrelated"
        unrelated.mkdir()
        keep = unrelated / ".keep"
        keep.write_bytes(b"unrelated evidence\x00")
        empty = self.root / "empty"
        empty.mkdir()
        file = self.root / "file"
        file.write_text("original")
        link = self.root / "link"
        link.symlink_to(empty, target_is_directory=True)
        dangling = self.root / "dangling"
        dangling.symlink_to(self.root / "missing", target_is_directory=True)

        for output in (unrelated, empty, file, link, f"{link}///", dangling,
                       f"{dangling}///"):
            with self.subTest(output=output):
                result = self.download(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("fresh", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertEqual(self.contents(unrelated), {".keep": b"unrelated evidence\x00"})
                self.assertEqual(list(empty.iterdir()), [])
                self.assertEqual(file.read_text(), "original")
                self.assertTrue(link.is_symlink())
                self.assertTrue(dangling.is_symlink())
                self.assertFalse((self.root / "missing").exists())

    def test_failed_or_interrupted_downloads_remain_marked_and_retry_is_fresh(self):
        for failure in ("exit", "signal"):
            with self.subTest(failure=failure):
                output = self.root / failure
                result = self.download(output, failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((output / ".incomplete").is_file())
                self.assertEqual((output / "log.ndjson").read_bytes(), APP_LOG)
                self.assertEqual((output / "widget-log.ndjson").read_bytes(),
                                 b'{"message":"interrupted')
                partial = self.contents(output)
                calls = self.calls.read_bytes()

                result = self.download(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls.read_bytes(), calls)
                self.assertEqual(self.contents(output), partial)

                retry = self.root / f"retry-{failure}"
                result = self.download(retry)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.contents(retry),
                                 {"log.ndjson": APP_LOG, "widget-log.ndjson": WIDGET_LOG})
                self.assertEqual(self.contents(output), partial)

    def test_listing_does_not_create_or_change_a_destination(self):
        output = self.root / "listing"
        result = self.download(output, selection=())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(output.exists())
        output.mkdir()
        (output / "keep").write_text("unrelated")
        result = self.download(output, selection=())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.contents(output), {"keep": b"unrelated"})

    def test_no_matching_attachments_does_not_create_a_destination(self):
        output = self.root / "no-match"
        result = self.download(output, event="second", selection=("--name", "widget-log.ndjson"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no matching attachments", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
