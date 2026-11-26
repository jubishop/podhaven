from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
import unittest

import hang_guard
import service_guard


SCRIPT = Path(__file__).resolve().parents[2] / ".agents/scripts/sentry-cli/close_sentry_issue.sh"
ISSUE = "artisanal-software/7001"
COMMIT = "970179c2d7eeeb2eb5d6ba0f82b03dbb4c1106a6"
WRITES = ("resolve", "unresolve", "archive")


class SentryCloseoutTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.calls = self.root / "calls.jsonl"
        self.state = self.root / "state.json"
        self.fake = self.root / "sentry"
        # Like Sentry, a commit resolution of an already resolved issue changes nothing.
        self.fake.write_text('''#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["CLOSEOUT_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
state_path = os.environ["CLOSEOUT_TEST_STATE"]
with open(state_path) as stream:
    state = json.load(stream)
mode = os.environ["CLOSEOUT_TEST_MODE"]
if args == ["auth", "status"]:
    sys.exit(0)
command = args[:2]
if command == ["issue", "view"]:
    if mode == "unreadable":
        sys.exit("Error: Issue 7001 not found.")
    print(json.dumps({"id": "7001", "status": state["status"], "statusDetails": state["statusDetails"]}))
    sys.exit(0)
if mode == "ignored-writes":
    sys.exit(0)
if command == ["issue", "unresolve"]:
    state = {"status": "unresolved", "statusDetails": {}}
elif command == ["issue", "archive"] and args[3:] == ["--until", "auto"]:
    state = {"status": "ignored", "statusDetails": {}}
elif command == ["issue", "resolve"] and args[3:] == ["--in", "@next"]:
    if mode == "next-fails":
        sys.exit("Error: Sentry request failed.")
    state = {"status": "resolved", "statusDetails": {"inNextRelease": True}}
elif command == ["issue", "resolve"] and args[3] == "--in" and args[4].startswith("@commit:jubishop/podhaven@"):
    if mode in ("rejected-commit", "next-fails"):
        sys.exit("Error: Unable to find the given commit.")
    if state["status"] != "resolved":
        state = {"status": "resolved", "statusDetails": {"inCommit": {"id": args[4].rsplit("@", 1)[1]}}}
else:
    sys.exit(f"Unexpected command: {args}")
with open(state_path, "w") as stream:
    json.dump(state, stream)
''')
        self.fake.chmod(0o755)

    def close(self, *arguments, status="unresolved", details=None, mode=""):
        self.state.write_text(json.dumps({"status": status, "statusDetails": details or {}}))
        return hang_guard.run(
            ["bash", str(SCRIPT), *arguments], capture_output=True, text=True, check=False,
            env={**os.environ, "SENTRY_BIN": str(self.fake), "CLOSEOUT_TEST_CALLS": str(self.calls),
                 "CLOSEOUT_TEST_STATE": str(self.state), "CLOSEOUT_TEST_MODE": mode},
        )

    def writes(self):
        if not self.calls.exists():
            return []
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return [call for call in calls if call[:1] == ["issue"] and call[1] in WRITES]

    def final_state(self):
        return json.loads(self.state.read_text())

    def test_commit_resolves_the_issue_in_the_merge_commit(self):
        result = self.close("7001", "--commit", COMMIT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(), [["issue", "resolve", ISSUE, "--in", f"@commit:jubishop/podhaven@{COMMIT}"]])
        self.assertEqual(self.final_state()["statusDetails"], {"inCommit": {"id": COMMIT}})
        self.assertIn(f"resolved in commit {COMMIT}", result.stdout)

    def test_commit_reopens_an_already_resolved_issue_so_sentry_records_the_commit(self):
        result = self.close("7001", "--commit", COMMIT, status="resolved", details={"inRelease": "1.0+1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[1] for call in self.writes()], ["unresolve", "resolve"])
        self.assertEqual(self.final_state()["statusDetails"], {"inCommit": {"id": COMMIT}})

    def test_a_rejected_commit_falls_back_to_the_next_release(self):
        result = self.close("7001", "--commit", COMMIT, mode="rejected-commit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes()[-1], ["issue", "resolve", ISSUE, "--in", "@next"])
        self.assertEqual(self.final_state()["status"], "resolved")
        self.assertIn("resolved in the next release", result.stdout)
        self.assertIn(f"rejected commit {COMMIT}", result.stdout)

    def test_next_resolves_the_issue_in_the_next_release(self):
        result = self.close("7001", "--next")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(), [["issue", "resolve", ISSUE, "--in", "@next"]])
        self.assertIn("resolved in the next release", result.stdout)

    def test_archive_ignores_the_issue_until_it_escalates(self):
        result = self.close("7001", "--archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(), [["issue", "archive", ISSUE, "--until", "auto"]])
        self.assertEqual(self.final_state()["status"], "ignored")
        self.assertIn("archived until it escalates", result.stdout)

    def test_a_closure_sentry_did_not_record_fails(self):
        for arguments in (("--commit", COMMIT), ("--next",), ("--archive",)):
            with self.subTest(arguments=arguments):
                result = self.close("7001", *arguments, mode="ignored-writes")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not record", result.stderr)

    def test_a_failed_resolution_fails(self):
        result = self.close("7001", "--commit", COMMIT, mode="next-fails")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.final_state()["status"], "unresolved")

    def test_an_unreadable_issue_fails_before_any_change(self):
        result = self.close("7001", "--archive", mode="unreadable")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])

    def test_invalid_arguments_change_nothing(self):
        for arguments in ((), ("7001",), ("PODHAVEN-6J", "--next"), ("7001", "--next", "--archive"),
                          ("7001", "--commit", COMMIT[:8]), ("7001", "--commit"), ("7001", "8001", "--next")):
            with self.subTest(arguments=arguments):
                result = self.close(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.calls.exists())

    def test_help_names_every_mode(self):
        result = self.close("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for mode in ("--commit", "--next", "--archive"):
            self.assertIn(mode, result.stdout)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
