import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import service_guard


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "bin/check-sentry-issues"
PERMALINK = "https://artisanal-software.sentry.io/issues/"
FINDINGS = "<!-- analyze-sentry-issue-findings:start -->\n<!-- analyze-sentry-issue-findings:end -->"


def sentry_issue(identifier, short_id):
    return {"id": identifier, "shortId": short_id, "permalink": f"{PERMALINK}{identifier}/"}


class CheckSentryIssuesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="check-sentry-issues-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:{os.environ['PATH']}",
            SENTRY_BIN=str(self.bin / "sentry"),
            CHECK_SENTRY_ISSUES_TEST=str(self.directory),
            RUNNER_TEMP=str(self.directory),
            GH_REPO="jubishop/podhaven",
        )
        self.env.pop("GITHUB_STEP_SUMMARY", None)
        for command in ("sentry", "gh"):
            self.stub(command)
        self.write("comments.json", [[]])

    def write(self, name, value):
        (self.directory / name).write_text(json.dumps(value))

    def writes(self):
        path = self.directory / "writes.json"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def stub(self, command):
        path = self.bin / command
        path.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys

directory = Path(os.environ["CHECK_SENTRY_ISSUES_TEST"])
command = Path(sys.argv[0]).name
arguments = sys.argv[1:]

def record(kind, **values):
    with (directory / "writes.json").open("a") as stream:
        stream.write(json.dumps({"kind": kind, **values}) + "\\n")

def option(name):
    return arguments[arguments.index(name) + 1]

if command == "sentry":
    if arguments[:2] == ["auth", "status"]:
        raise SystemExit(0)
    (directory / "sentry.args").write_text(json.dumps(arguments))
    print((directory / "sentry.json").read_text())
elif arguments[0] == "api":
    endpoint = arguments[-1]
    if endpoint.startswith("repos/jubishop/podhaven/issues?"):
        print((directory / "issues.json").read_text())
    else:
        record("comments-read", endpoint=endpoint)
        print((directory / "comments.json").read_text())
elif arguments[:2] == ["issue", "edit"]:
    record("label", issue=arguments[2], label=option("--add-label"))
elif arguments[:2] == ["issue", "create"]:
    record("create", title=option("--title"), label=option("--label"),
           body=Path(option("--body-file")).read_text())
    print("https://github.com/jubishop/podhaven/issues/900")
elif arguments[:2] == ["issue", "comment"]:
    record("comment", issue=arguments[2], body=Path(option("--body-file")).read_text())
else:
    raise SystemExit(97)
''')
        path.chmod(0o755)

    def run_check(self, **environment):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT)], cwd=ROOT, env={**self.env, **environment},
            text=True, capture_output=True, timeout=30,
        )

    def test_creates_intake_for_untracked_issue_ignoring_mentions_and_pull_requests(self):
        self.write("sentry.json", {"data": [sentry_issue("7001", "PODHAVEN-A1")], "hasMore": False})
        self.write("issues.json", [[
            {"number": 10, "state": "open", "labels": [], "body": "Mentions PODHAVEN-A1 only"},
            {"number": 11, "state": "open", "labels": [], "pull_request": {},
             "body": "<!-- sentry-issue:7001 -->"},
        ]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        create, comment = self.writes()
        self.assertEqual(create["kind"], "create")
        self.assertEqual(create["title"], "Triage Sentry issue PODHAVEN-A1")
        self.assertEqual(create["label"], "sentry-issue")
        self.assertTrue(create["body"].startswith("<!-- sentry-issue:7001 -->\n"))
        self.assertIn(f"[PODHAVEN-A1]({PERMALINK}7001/)", create["body"])
        self.assertEqual(comment["kind"], "comment")
        self.assertEqual(comment["issue"], "https://github.com/jubishop/podhaven/issues/900")
        self.assertIn("<!-- snissue:7001 -->", comment["body"])
        self.assertIn("<!-- fix-issue-prerequisite: analyze-sentry-issue 7001 -->", comment["body"])
        self.assertIn("`bin/snissue 7001`", comment["body"])
        self.assertIn("created 1 intake issue(s)", result.stdout)

    def test_open_intake_gets_label_and_one_instruction_comment(self):
        self.write("sentry.json", {"data": [sentry_issue("7002", "PODHAVEN-A2")], "hasMore": False})
        self.write("issues.json", [[
            {"number": 20, "state": "open", "labels": [],
             "body": "<!-- sentry-issue:7002 -->\n<!-- analyze-sentry-issue-findings:start -->"},
        ]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        writes = self.writes()
        self.assertEqual(writes[0], {"kind": "label", "issue": "20", "label": "sentry-issue"})
        self.assertEqual(writes[1]["kind"], "comments-read")
        self.assertEqual(writes[2]["kind"], "comment")
        self.assertEqual(writes[2]["issue"], "20")
        self.assertEqual(len(writes), 3)

        (self.directory / "writes.json").unlink()
        self.write("comments.json", [[{"body": "<!-- snissue:7002 -->\nInstructions"}]])
        self.write("issues.json", [[
            {"number": 20, "state": "open", "labels": [{"name": "sentry-issue"}],
             "body": "<!-- sentry-issue:7002 -->"},
        ]])
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([write["kind"] for write in self.writes()], ["comments-read"])

    def test_analyzed_issues_need_no_comment(self):
        self.write("sentry.json", {"data": [
            sentry_issue("7003", "PODHAVEN-A3"),
            sentry_issue("7004", "PODHAVEN-A4"),
        ], "hasMore": False})
        self.write("issues.json", [[
            {"number": 30, "state": "open", "labels": [{"name": "sentry-issue"}],
             "body": "<!-- sentry-issue:7003 -->\n" + FINDINGS},
            {"number": 31, "state": "open", "labels": [{"name": "bug"}],
             "body": f"Legacy analysis of {PERMALINK}7004/events/abc/\n\n## Sentry closeout\n\nResolve it."},
        ]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.writes(), [{"kind": "label", "issue": "31", "label": "sentry-issue"}])
        self.assertIn("Already analyzed: PODHAVEN-A3 in issue #30", result.stdout)
        self.assertIn("Already analyzed: PODHAVEN-A4 in issue #31", result.stdout)

    def test_open_tracking_issue_wins_over_closed_ones(self):
        self.write("sentry.json", {"data": [sentry_issue("7005", "PODHAVEN-A5")], "hasMore": False})
        self.write("issues.json", [[
            {"number": 41, "state": "closed", "labels": [{"name": "sentry-issue"}],
             "body": "<!-- sentry-issue:7005 -->\n" + FINDINGS},
            {"number": 40, "state": "open", "labels": [{"name": "sentry-issue"}],
             "body": f"{PERMALINK}7005/\n\n## Sentry closeout"},
        ]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.writes(), [])
        self.assertIn("Already analyzed: PODHAVEN-A5 in issue #40", result.stdout)

    def test_recurrence_after_closed_tracking_opens_linked_intake(self):
        self.write("sentry.json", {"data": [sentry_issue("7006", "PODHAVEN-A6")], "hasMore": False})
        self.write("issues.json", [[
            {"number": 52, "state": "closed", "labels": [], "body": f"See {PERMALINK}7006/"},
            {"number": 51, "state": "closed", "labels": [{"name": "sentry-issue"}],
             "body": "<!-- sentry-issue:7006 -->\n" + FINDINGS},
        ]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        create, comment = self.writes()
        self.assertEqual(create["title"], "Triage recurrence of Sentry issue PODHAVEN-A6")
        self.assertEqual(create["label"], "sentry-issue")
        self.assertTrue(create["body"].startswith("<!-- sentry-issue:7006 -->\n"))
        self.assertIn("#51, #52", create["body"])
        self.assertIn("<!-- fix-issue-prerequisite: analyze-sentry-issue 7006 -->", comment["body"])
        self.assertIn("created 1 recurrence issue(s)", result.stdout)

    def test_dry_run_writes_nothing(self):
        self.write("sentry.json", {"data": [
            sentry_issue("7007", "PODHAVEN-A7"),
            sentry_issue("7008", "PODHAVEN-A8"),
        ], "hasMore": False})
        self.write("issues.json", [[
            {"number": 60, "state": "closed", "labels": [], "body": f"{PERMALINK}7008/"},
        ]])

        result = self.run_check(DRY_RUN="true")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.writes(), [])
        self.assertIn("Would create issue: Triage Sentry issue PODHAVEN-A7", result.stdout)
        self.assertIn("Would create issue: Triage recurrence of Sentry issue PODHAVEN-A8 (after #60)", result.stdout)

    def test_lists_unresolved_issues_except_feedback_and_probe_only_issues(self):
        self.write("sentry.json", {"data": [], "hasMore": False})
        self.write("issues.json", [[]])

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        arguments = json.loads((self.directory / "sentry.args").read_text())
        self.assertEqual(arguments[:3], ["issue", "list", "artisanal-software/podhaven"])
        self.assertEqual(arguments[arguments.index("--query") + 1],
                         "is:unresolved !issue.category:feedback !has:diagnostic-run")
        self.assertEqual(arguments[arguments.index("--fields") + 1], "id,shortId,permalink")

    def test_every_sentry_probe_tags_its_diagnostic_run(self):
        probes = [path for path in sorted((ROOT / "bin/integration").glob("*/*.swift"))
                  if "SentrySDK.start" in path.read_text()]
        self.assertTrue(probes)
        for probe in probes:
            with self.subTest(probe=probe.relative_to(ROOT)):
                self.assertTrue('scope.setTag(value: run, key: "diagnostic-run")' in probe.read_text(),
                                "Sentry intake skips probe events only by their diagnostic-run tag")

    def test_skill_lists_the_same_issues_as_the_checker(self):
        skill = (ROOT / ".agents/skills/analyze-sentry-issue/SKILL.md").read_text()
        self.assertIn("--query 'is:unresolved !issue.category:feedback !has:diagnostic-run'", skill)

    def test_skill_trusts_the_checker_comment_author(self):
        skill = (ROOT / ".agents/skills/analyze-sentry-issue/SKILL.md").read_text()
        self.assertIn("<!-- fix-issue-trusted-marker-author: github-actions[bot] -->", skill)
        self.assertIn("<!-- fix-issue-prerequisite: analyze-sentry-issue <numeric-id> -->", skill)

    def test_partial_and_invalid_sentry_lists_are_rejected(self):
        self.write("issues.json", [[]])
        for payload in (
            {"data": [sentry_issue("7009", "PODHAVEN-A9")], "hasMore": True},
            {"data": [{"id": "unsafe", "shortId": "PODHAVEN-A9", "permalink": PERMALINK}]},
            {"data": {}},
        ):
            with self.subTest(payload=payload):
                self.write("sentry.json", payload)
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.writes(), [])


if __name__ == "__main__":
    unittest.main()
