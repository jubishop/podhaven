import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "bin/snissue"
FISH = shutil.which("fish")


class SentryIssueLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="snissue-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin), SNISSUE_TEST=str(self.directory))
        for command in ("git", "jq", "seq"):
            (self.bin / command).symlink_to(shutil.which(command))
        for command in ("sentry", "gh", "codex", "fzf"):
            self.stub(command)
        self.write("sentry.json", {
            "data": [
                {"id": "1001", "shortId": "PODHAVEN-AA", "title": "Synthetic old issue",
                 "level": "warning", "count": "12", "userCount": 3},
                {"id": "1003", "shortId": "PODHAVEN-AC", "title": "Synthetic\nnew\tissue",
                 "level": "error", "count": "4", "userCount": 2},
                {"id": "1002", "shortId": "PODHAVEN-AB", "title": "Synthetic middle issue"},
            ],
            "hasMore": False,
        })
        self.write("gh.json", [[
            {"number": 90, "state": "open", "title": "PODHAVEN-AC", "body": "PR",
             "pull_request": {}},
            {"number": 91, "state": "open", "title": "PODHAVEN-AC0", "body": ""},
            {"number": 92, "state": "open", "title": "", "body": "https://artisanal-software.sentry.io/issues/10030/"},
            {"number": 93, "state": "open", "title": "PODHAVEN-AC", "body": "Reference only"},
        ], [
            {"number": 42, "state": "closed", "title": "Tracked issue",
             "body": "https://artisanal-software.sentry.io/issues/1003/?query=is%3Aunresolved"},
            {"number": 43, "state": "open", "title": "Investigate PODHAVEN-AA", "body": None},
        ]])

    def write(self, name, value):
        (self.directory / name).write_text(json.dumps(value))

    def read(self, name):
        return json.loads((self.directory / name).read_text())

    def stub(self, command):
        path = self.bin / command
        path.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys

directory = Path(os.environ["SNISSUE_TEST"])
command = Path(sys.argv[0]).name
with (directory / "calls").open("a") as stream:
    stream.write(command + "\\n")
(directory / (command + ".args")).write_text(json.dumps(sys.argv[1:]))
if os.environ.get("SNISSUE_FAIL") == command:
    raise SystemExit(17)
if command == "codex":
    (directory / "codex.cwd").write_text(json.dumps(os.getcwd()))
elif command == "fzf":
    rows = sys.stdin.read().splitlines()
    (directory / "picker.json").write_text(json.dumps(rows))
    if rows:
        print(rows[int(os.environ.get("SNISSUE_SELECT", "0"))])
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

    def assert_launched(self, result, reference):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.read("codex.cwd"), str(ROOT))
        self.assertEqual(self.read("codex.args"), [
            "--dangerously-bypass-approvals-and-sandbox",
            f"$analyze-sentry-issue {reference}",
        ])

    def assert_stopped(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertFalse((self.directory / "codex.args").exists())

    def test_direct_references_launch_from_checkout_root_without_discovery(self):
        for reference, expected in (
            ("1003", "1003"),
            ("podhaven-ac", "PODHAVEN-AC"),
            ("https://artisanal-software.sentry.io/issues/1003/?query=is%3Aunresolved", "1003"),
            ("https://sentry.io/organizations/artisanal-software/issues/1003/", "1003"),
        ):
            with self.subTest(reference=reference):
                self.assert_launched(self.run_command(reference), expected)
        self.assertEqual((self.directory / "calls").read_text().splitlines(), ["codex"] * 4)

    def test_invalid_references_never_launch(self):
        for reference in (
            "PODHAVEN-", "OTHER-AC", "1003 extra instructions", "--helpful",
            "https://example.com/issues/1003/", "https://sentry.io.evil.test/issues/1003/",
            "https://artisanal-software.sentry.io/issues/feedback/?feedbackSlug=podhaven:1003",
            "https://artisanal-software.sentry.io/issues/1003evil/",
        ):
            with self.subTest(reference=reference):
                self.assert_stopped(self.run_command(reference), "not a PodHaven issue")

    def test_help_and_extra_arguments(self):
        for flag in ("--help", "-h"):
            result = self.run_command(flag)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Usage: snissue", result.stdout)
        self.assert_stopped(self.run_command("1003", "1001"), "Usage: snissue")

    def test_picker_sorts_and_shows_impact_and_tracking(self):
        self.assert_launched(self.run_command(), "1003")
        rows = self.read("picker.json")
        self.assertEqual([row.split("\t", 1)[0] for row in rows], ["1003", "1002", "1001"])
        self.assertIn("Synthetic new issue", rows[0])
        self.assertIn("4 events; 2 users", rows[0])
        self.assertIn("GitHub: #42 closed", rows[0])
        self.assertIn("GitHub: untracked", rows[1])
        self.assertIn("GitHub: #43 open", rows[2])
        self.assertEqual(self.read("sentry.args"), [
            "issue", "list", "artisanal-software/podhaven",
            "--query", "is:unresolved !issue.category:feedback",
            "--period", "365d", "--limit", "1000", "--sort", "new", "--fresh", "--json",
            "--fields", "id,shortId,title,level,count,userCount",
        ])
        self.assertEqual(self.read("gh.args"), [
            "api", "--paginate", "--slurp", "repos/jubishop/podhaven/issues?state=all&per_page=100",
        ])
        calls = (self.directory / "calls").read_text().splitlines()
        self.assertEqual(calls.count("gh"), 1)
        self.assertEqual(calls.count("sentry"), 1)

    def test_picker_launches_selected_row(self):
        self.env["SNISSUE_SELECT"] = "2"
        self.assert_launched(self.run_command(), "1001")

    def test_bare_array_response_and_missing_optional_fields(self):
        self.write("sentry.json", [{"id": "1001", "shortId": "PODHAVEN-AA"}])
        self.assert_launched(self.run_command(), "1001")
        self.assertIn("(no title)", self.read("picker.json")[0])
        self.assertIn("? events; ? users", self.read("picker.json")[0])

    def test_empty_list_does_not_fetch_github(self):
        self.write("sentry.json", {"data": [], "hasMore": False})
        self.assert_stopped(self.run_command(), "No unresolved Sentry issues found")
        self.assertFalse((self.directory / "gh.args").exists())

    def test_partial_list_is_rejected(self):
        payload = self.read("sentry.json")
        payload["hasMore"] = True
        self.write("sentry.json", payload)
        self.assert_stopped(self.run_command(), "refusing to show a partial list")

    def test_invalid_sentry_data_is_rejected(self):
        for payload in ("invalid json", '{}', '{"data": {}}', '{"data": [{"id": "unsafe"}]}'):
            with self.subTest(payload=payload):
                (self.directory / "sentry.json").write_text(payload)
                self.assert_stopped(self.run_command(), "invalid issue data")

    def test_invalid_github_data_is_rejected(self):
        self.write("gh.json", {"error": "synthetic failure"})
        self.assert_stopped(self.run_command(), "invalid issue data")

    def test_failed_dependencies_and_cancel_never_launch(self):
        for command, message in (
            ("sentry", "could not fetch unresolved"),
            ("gh", "could not fetch PodHaven GitHub issues"),
            ("fzf", "No issue selected"),
        ):
            with self.subTest(command=command):
                self.env["SNISSUE_FAIL"] = command
                self.assert_stopped(self.run_command(), message)

    def test_numbered_fallback(self):
        (self.bin / "fzf").unlink()
        self.assert_launched(self.run_command(input="2\n"), "1002")

    def test_invalid_numbered_selections(self):
        (self.bin / "fzf").unlink()
        for selection in ("0\n", "4\n", "text\n", ""):
            with self.subTest(selection=selection):
                result = self.run_command(input=selection)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.directory / "codex.args").exists())

    def test_codex_exit_status_is_preserved(self):
        self.env["SNISSUE_FAIL"] = "codex"
        self.assertEqual(self.run_command("1003").returncode, 17)


if __name__ == "__main__":
    unittest.main()
