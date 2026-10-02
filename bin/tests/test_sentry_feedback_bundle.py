from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / ".agents/scripts/sentry-cli/fetch_feedback_bundle.sh"
)


class SentryFeedbackBundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.calls = self.root / "calls.jsonl"
        self.fake = self.root / "sentry"
        self.fake.write_text("""#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["FEEDBACK_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
event = {"id": os.environ["FEEDBACK_TEST_EVENT"], "tags": []}
if args == ["auth", "status"]:
    sys.exit(0)
elif args[:2] == ["issue", "view"]:
    payload = {"id": args[2], "title": "Synthetic feedback"}
elif args[:2] == ["issue", "events"]:
    payload = {"data": [] if os.environ["FEEDBACK_TEST_FALLBACK"] == "1" else [event]}
elif args[0] == "api":
    endpoint = args[1]
    if "/events/?" in endpoint:
        body = [event]
    elif endpoint.endswith("/activities/"):
        body = {"activity": []}
    elif endpoint.endswith(("/notes/", "/attachments/")):
        body = []
    else:
        sys.exit(f"Unexpected endpoint: {endpoint}")
    payload = {"status": 200, "statusText": "OK", "body": body}
else:
    sys.exit(f"Unexpected command: {args}")
print(json.dumps(payload))
""")
        self.fake.chmod(0o755)

    def fetch(self, output, *, issue="456", event="second-event", fallback=False):
        return subprocess.run(
            ["bash", str(SCRIPT), f"podhaven:{issue}", "--out", str(output)],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
            env={
                **os.environ,
                "SENTRY_BIN": str(self.fake),
                "FEEDBACK_TEST_CALLS": str(self.calls),
                "FEEDBACK_TEST_EVENT": event,
                "FEEDBACK_TEST_FALLBACK": str(int(fallback)),
            },
        )

    def test_repeated_fetch_preserves_prior_bundle_and_requires_fresh_output(self):
        for fallback in (False, True):
            with self.subTest(first_fetch_fallback=fallback):
                output = self.root / f"first-{fallback}"
                first = self.fetch(output, issue="123", event="first-event", fallback=fallback)
                self.assertEqual(first.returncode, 0, first.stderr)
                original = {path.name: path.read_bytes() for path in output.iterdir()}
                self.assertIn("event_first-event.json", original)
                self.assertEqual("events_raw.json" in original, fallback)
                prior_calls = self.calls.read_bytes()

                second = self.fetch(output)

                self.assertNotEqual(second.returncode, 0, second.stdout)
                self.assertIn("output directory", second.stderr)
                self.assertEqual(self.calls.read_bytes(), prior_calls)
                self.assertEqual(
                    {path.name: path.read_bytes() for path in output.iterdir()}, original
                )

                fresh = self.root / f"independent-{fallback}" / "bundle"
                result = self.fetch(fresh)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    sorted(path.name for path in fresh.glob("event_*.json")),
                    ["event_second-event.json"],
                )
                self.assertFalse((fresh / "events_raw.json").exists())
                self.assertEqual(
                    json.loads((fresh / "events.json").read_text())["data"][0]["id"],
                    "second-event",
                )

    def test_existing_paths_are_preserved_before_any_sentry_call(self):
        directory = self.root / "unrelated"
        directory.mkdir()
        hidden = directory / ".keep"
        hidden.write_bytes(b"keep this unrelated file\x00")
        empty = self.root / "empty"
        empty.mkdir()
        file = self.root / "file"
        file.write_text("original evidence")
        link = self.root / "link"
        link.symlink_to(empty, target_is_directory=True)
        dangling = self.root / "dangling"
        dangling.symlink_to(self.root / "missing", target_is_directory=True)

        for output in (directory, empty, file, link, f"{link}/", dangling):
            with self.subTest(output=output):
                result = self.fetch(output)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("output directory", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertEqual(hidden.read_bytes(), b"keep this unrelated file\x00")
                self.assertEqual(list(directory.iterdir()), [hidden])
                self.assertEqual(list(empty.iterdir()), [])
                self.assertEqual(file.read_text(), "original evidence")
                self.assertTrue(link.is_symlink())
                self.assertTrue(dangling.is_symlink())
                self.assertFalse((self.root / "missing").exists())

    def test_output_argument_is_required_before_authentication(self):
        for arguments in ([], ["--out"], ["--out", ""]):
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    ["bash", str(SCRIPT), "podhaven:123", *arguments],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    check=False,
                    env={**os.environ, "SENTRY_BIN": str(self.root / "missing-sentry")},
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--out DIR", result.stderr)
                self.assertNotIn("auth", result.stderr)


if __name__ == "__main__":
    unittest.main()
