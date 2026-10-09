import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "bin/snfeedback"
FISH = shutil.which("fish")
PERMALINK = "https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven%3A"
FINDINGS = "<!-- analyze-sentry-feedback-findings:start -->\n<!-- analyze-sentry-feedback-findings:end -->"


class SentryFeedbackLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="snfeedback-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin), SNFEEDBACK_TEST=str(self.directory))
        for command in ("git", "jq", "seq"):
            (self.bin / command).symlink_to(shutil.which(command))
        for command in ("sentry", "gh", "claude", "fzf"):
            self.stub(command)
        self.write("sentry.json", {
            "data": [
                {"id": "2001", "shortId": "PODHAVEN-FA", "permalink": PERMALINK + "2001",
                 "metadata": {"message": "Synthetic old report", "contact_email": "old@example.com"}},
                {"id": "2004", "shortId": "PODHAVEN-FD", "permalink": PERMALINK + "2004",
                 "metadata": {"message": "Synthetic\nnew\treport", "contact_email": "new@example.com"}},
                {"id": "2002", "shortId": "PODHAVEN-FB", "permalink": PERMALINK + "2002",
                 "title": "Synthetic title fallback"},
                {"id": "2003", "shortId": "PODHAVEN-FC", "permalink": PERMALINK + "2003",
                 "metadata": {"message": "Synthetic closed report"}},
            ],
            "hasMore": False,
        })
        self.write("gh.json", [[
            {"number": 90, "state": "open", "body": "<!-- sentry-feedback:podhaven:2001 -->",
             "pull_request": {}},
            {"number": 99, "state": "open", "body": PERMALINK + "2004\n" + FINDINGS},
            {"number": 42, "state": "open",
             "body": "<!-- sentry-feedback:podhaven:2004 -->\n<!-- analyze-sentry-feedback-findings:start -->"},
        ], [
            {"number": 50, "state": "closed", "body": "<!-- sentry-feedback:podhaven:2003 -->\n" + FINDINGS},
            {"number": 61, "state": "open", "body": PERMALINK + "2002\n" + FINDINGS},
        ]])

    def write(self, name, value):
        (self.directory / name).write_text(json.dumps(value))

    def read(self, name):
        return json.loads((self.directory / name).read_text())

    def calls(self):
        return (self.directory / "calls").read_text().splitlines()

    def stub(self, command):
        path = self.bin / command
        path.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys

directory = Path(os.environ["SNFEEDBACK_TEST"])
command = Path(sys.argv[0]).name
with (directory / "calls").open("a") as stream:
    stream.write(command + "\\n")
(directory / (command + ".args")).write_text(json.dumps(sys.argv[1:]))
if os.environ.get("SNFEEDBACK_FAIL") == command:
    raise SystemExit(17)
if command == "claude":
    (directory / "claude.cwd").write_text(json.dumps(os.getcwd()))
elif command == "fzf":
    rows = sys.stdin.read().splitlines()
    (directory / "picker.json").write_text(json.dumps(rows))
    if rows:
        print(rows[int(os.environ.get("SNFEEDBACK_SELECT", "0"))])
else:
    print((directory / (command + ".json")).read_text())
''')
        path.chmod(0o755)

    def run_command(self, *arguments, input=None):
        return subprocess.run(
            [FISH, "--no-config", str(SCRIPT), *arguments],
            cwd=ROOT / "PodHavenTests", env=self.env,
            input=input, text=True, capture_output=True, timeout=15,
        )

    def assert_launched(self, result, slug):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(self.read("claude.cwd"), str(ROOT))
        self.assertEqual(self.read("claude.args"), [
            "--dangerously-skip-permissions",
            f"/analyze-sentry-feedback {slug}",
        ])

    def assert_stopped(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertFalse((self.directory / "claude.args").exists())

    def test_direct_references_launch_from_checkout_root_without_discovery(self):
        for reference in (
            "7485822944",
            "PodHaven:7485822944",
            PERMALINK + "7485822944",
            "https://sentry.io/organizations/artisanal-software/feedback/?project=1&feedbackSlug=PODHAVEN:7485822944",
        ):
            with self.subTest(reference=reference):
                self.assert_launched(self.run_command(reference), "podhaven:7485822944")
        self.assertEqual(self.calls(), ["claude"] * 4)

    def test_invalid_references_never_launch(self):
        for reference in (
            "podhaven:", "other:123", "podhaven:12a", "PODHAVEN-3K", "123 extra instructions", "--helpful",
            "https://example.com/?feedbackSlug=podhaven:123",
            "https://sentry.io.evil.test/?feedbackSlug=podhaven:123",
            "https://evilsentry.io/?feedbackSlug=podhaven:123",
            "https://artisanal-software.sentry.io/issues/123/",
            PERMALINK + "123%26evil",
        ):
            with self.subTest(reference=reference):
                self.assert_stopped(self.run_command(reference), "not a PodHaven feedback slug")
        self.assertFalse((self.directory / "calls").exists())

    def test_extra_arguments_show_usage(self):
        self.assert_stopped(self.run_command("2004", "2001"), "Usage: snfeedback")

    def test_picker_sorts_and_shows_reports_and_tracking(self):
        self.assert_launched(self.run_command(), "podhaven:2004")
        rows = self.read("picker.json")
        self.assertEqual([row.split("\t", 1)[0] for row in rows],
                         ["podhaven:2004", "podhaven:2003", "podhaven:2002", "podhaven:2001"])
        self.assertIn('"Synthetic new report"', rows[0])
        self.assertIn("new@example.com; GitHub: #42 intake", rows[0])
        self.assertIn("anonymous; GitHub: #50 closed", rows[1])
        self.assertIn('"Synthetic title fallback"', rows[2])
        self.assertIn("GitHub: #61 analyzed", rows[2])
        self.assertIn("old@example.com; GitHub: untracked", rows[3])
        self.assertEqual(self.read("sentry.args"), [
            "issue", "list", "artisanal-software/podhaven",
            "--query", "issue.category:feedback is:unresolved",
            "--period", "365d", "--limit", "1000", "--fresh", "--json",
            "--fields", "id,shortId,metadata,permalink",
        ])
        self.assertEqual(self.read("gh.args"), [
            "api", "--paginate", "--slurp", "repos/jubishop/podhaven/issues?state=all&per_page=100",
        ])
        self.assertEqual(self.calls(), ["sentry", "gh", "fzf", "claude"])

    def test_picker_launches_selected_row(self):
        self.env["SNFEEDBACK_SELECT"] = "2"
        self.assert_launched(self.run_command(), "podhaven:2002")

    def test_bare_array_response_and_missing_optional_fields(self):
        self.write("sentry.json", [{"id": "2001", "permalink": PERMALINK + "2001"}])
        self.assert_launched(self.run_command(), "podhaven:2001")
        row = self.read("picker.json")[0]
        self.assertIn("PODHAVEN-?", row)
        self.assertIn('"(no message)"', row)
        self.assertIn("anonymous; GitHub: untracked", row)

    def test_empty_list_stops(self):
        self.write("sentry.json", {"data": [], "hasMore": False})
        self.assert_stopped(self.run_command(), "No unresolved Sentry feedback found")

    def test_partial_list_is_rejected(self):
        payload = self.read("sentry.json")
        payload["hasMore"] = True
        self.write("sentry.json", payload)
        self.assert_stopped(self.run_command(), "refusing to show a partial list")

    def test_invalid_sentry_data_is_rejected(self):
        for payload, message in (
            ("invalid json", "invalid feedback data"),
            ('{"data": {}}', "invalid feedback data"),
            ('{"data": [{"id": "unsafe"}]}', "invalid feedback data"),
            ('{"data": [{"id": "1e3"}]}', "invalid feedback row"),
        ):
            with self.subTest(payload=payload):
                (self.directory / "sentry.json").write_text(payload)
                self.assert_stopped(self.run_command(), message)

    def test_invalid_github_data_is_rejected(self):
        self.write("gh.json", {"error": "synthetic failure"})
        self.assert_stopped(self.run_command(), "invalid issue data")

    def test_failed_dependencies_and_cancel_never_launch(self):
        for command, message in (
            ("sentry", "could not fetch unresolved PodHaven feedback"),
            ("gh", "could not fetch PodHaven GitHub issues"),
            ("fzf", "No feedback selected"),
        ):
            with self.subTest(command=command):
                self.env["SNFEEDBACK_FAIL"] = command
                self.assert_stopped(self.run_command(), message)

    def test_missing_claude_never_launches(self):
        (self.bin / "claude").unlink()
        self.assert_stopped(self.run_command("2004"), "claude is required")

    def test_numbered_fallback(self):
        (self.bin / "fzf").unlink()
        self.assert_launched(self.run_command(input="2\n"), "podhaven:2003")

    def test_invalid_numbered_selections(self):
        (self.bin / "fzf").unlink()
        for selection in ("0\n", "5\n", "text\n", ""):
            with self.subTest(selection=selection):
                result = self.run_command(input=selection)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.directory / "claude.args").exists())

    def test_claude_exit_status_is_preserved(self):
        self.env["SNFEEDBACK_FAIL"] = "claude"
        self.assertEqual(self.run_command("2004").returncode, 17)


if __name__ == "__main__":
    unittest.main()
