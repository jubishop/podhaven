"""Run bin/check-mcp-releases in a disposable checkout against a fake npm registry and a fake gh."""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

import hang_guard
import service_guard


SCRIPT = Path(__file__).resolve().parents[2] / "bin/check-mcp-releases"
PACKAGE = "@example/server"
SOURCE = "https://github.com/example/server"
BY_BOT = {"user": {"login": "github-actions[bot]", "type": "Bot"}}
BY_OWNER = {"user": {"login": "JubiShop", "type": "User"}}
BY_STRANGER = {"user": {"login": "stranger", "type": "User"}}


def packument(latest, heads):
    return {"dist-tags": {"latest": latest}, "repository": {"type": "git", "url": f"git+{SOURCE}.git"},
            "versions": {version: {"gitHead": head} if head else {} for version, head in heads.items()}}


def tracking_body(version, package=PACKAGE):
    return f"<!-- mcp-release:{package} -->\r\n<!-- mcp-release-version:{version} -->\r\nReview it."


class CheckMCPReleasesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="check-mcp-releases-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.repo = self.directory / "repo"
        (self.repo / "bin").mkdir(parents=True)
        shutil.copy2(SCRIPT, self.repo / "bin/check-mcp-releases")
        self.fakes = self.directory / "fakes"
        self.fakes.mkdir()
        self.summary = self.directory / "summary.md"
        self.env = dict(os.environ, PATH=f"{self.fakes}{os.pathsep}{os.environ['PATH']}",
                        CHECK_MCP_RELEASES_TEST=str(self.directory), GH_REPO="jubishop/podhaven",
                        GITHUB_STEP_SUMMARY=str(self.summary))
        for command in ("curl", "gh"):
            self.fake(command)
        self.configure(f"{PACKAGE}@1.0.0")
        self.write("registry.json", {})
        self.write("issues.json", [[]])

    def configure(self, *packages):
        servers = {f"server{index}": {"command": "npx", "args": ["-y", package]}
                   for index, package in enumerate(packages)}
        servers["local"] = {"command": "node", "args": ["server.js"]}
        for configuration in (".mcp.json", ".cursor/mcp.json"):
            (self.repo / configuration).parent.mkdir(exist_ok=True)
            (self.repo / configuration).write_text(json.dumps({"mcpServers": servers}))
        (self.repo / ".codex").mkdir(exist_ok=True)
        (self.repo / ".codex/config.toml").write_text("".join(
            f"[mcp_servers.{name}]\ncommand = {json.dumps(server['command'])}\nargs = {json.dumps(server['args'])}\n"
            for name, server in servers.items()))

    def write(self, name, value):
        (self.directory / name).write_text(json.dumps(value))

    def calls(self, kind=None):
        path = self.directory / "calls.json"
        calls = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        path.unlink(missing_ok=True)
        return [call for call in calls if kind is None or call["kind"] == kind]

    def fake(self, command):
        path = self.fakes / command
        path.write_text(f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import sys

directory = Path(os.environ["CHECK_MCP_RELEASES_TEST"])
command = Path(sys.argv[0]).name
arguments = sys.argv[1:]

def record(kind, **values):
    with (directory / "calls.json").open("a") as stream:
        stream.write(json.dumps({"kind": kind, **values}) + "\\n")

def option(name):
    return arguments[arguments.index(name) + 1]

if command == "curl":
    url = arguments[-1]
    record("curl", url=url)
    registry = json.loads((directory / "registry.json").read_text())
    package = url.removeprefix("https://registry.npmjs.org/")
    if package not in registry:
        print("curl: (22) The requested URL returned error: 404", file=sys.stderr)
        raise SystemExit(22)
    document = registry[package]
    print(document if isinstance(document, str) else json.dumps(document))
elif arguments[0] == "api":
    record("list", endpoint=arguments[-1])
    print((directory / "issues.json").read_text())
elif arguments[:2] == ["issue", "create"]:
    assert option("--body-file") == "-"
    record("create", repo=option("--repo"), title=option("--title"), label=option("--label"), body=sys.stdin.read())
    print("https://github.com/jubishop/podhaven/issues/900")
elif arguments[:2] == ["issue", "edit"]:
    assert option("--body-file") == "-"
    record("edit", issue=arguments[2], title=option("--title"), body=sys.stdin.read())
else:
    raise SystemExit(97)
''')
        path.chmod(0o755)

    def run_check(self, *arguments):
        return hang_guard.run([str(self.repo / "bin/check-mcp-releases"), *arguments], cwd=self.directory,
                              env=self.env, text=True, capture_output=True)

    def test_newer_release_opens_one_issue_naming_it(self):
        self.write("registry.json", {PACKAGE: packument("1.2.0", {"1.0.0": "a" * 40, "1.2.0": "b" * 40})})
        self.write("issues.json", [[
            {"number": 10, "state": "open", **BY_STRANGER, "body": tracking_body("1.2.0")},
            {"number": 11, "state": "open", **BY_BOT, "pull_request": {}, "body": tracking_body("1.2.0")},
        ], [
            {"number": 12, "state": "open", **BY_OWNER,
             "body": f"Find it by a marker such as `<!-- mcp-release:{PACKAGE} -->`."},
            {"number": 13, "state": "open", **BY_OWNER,
             "body": f"The checker writes bodies like this:\n\n```\n{tracking_body('1.1.0')}\n```\n"},
        ]])

        result = self.run_check("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call["kind"] for call in self.calls()], ["curl", "list"])
        self.assertIn(f"Would create an issue labeled p3: Review and bump the {PACKAGE} pin to 1.2.0", result.stdout)

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        curl, listing, create = self.calls()
        self.assertEqual(curl, {"kind": "curl", "url": f"https://registry.npmjs.org/{PACKAGE}"})
        self.assertEqual(listing["endpoint"], "repos/jubishop/podhaven/issues?state=all&per_page=100")
        self.assertEqual(create["repo"], "jubishop/podhaven")
        self.assertEqual(create["title"], f"Review and bump the {PACKAGE} pin to 1.2.0")
        self.assertEqual(create["label"], "p3")
        self.assertTrue(create["body"].startswith(
            f"<!-- mcp-release:{PACKAGE} -->\n<!-- mcp-release-version:1.2.0 -->\n"), create["body"])
        self.assertIn("newer than the 1.0.0 that", create["body"])
        self.assertIn(f"[1.0.0...1.2.0]({SOURCE}/compare/{'a' * 40}...{'b' * 40})", create["body"])
        self.assertIn(f"`npm diff --diff={PACKAGE}@1.0.0 --diff={PACKAGE}@1.2.0`", create["body"])
        self.assertIn("created 1 issue(s)", result.stdout)
        self.assertIn("## MCP release check", self.summary.read_text())

    def test_changes_link_falls_back_to_npm_without_published_commits(self):
        self.write("registry.json", {PACKAGE: packument("1.2.0", {"1.0.0": None, "1.2.0": "b" * 40})})

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        create, = self.calls("create")
        self.assertIn(f"(https://www.npmjs.com/package/{PACKAGE}?activeTab=versions)", create["body"])

    def test_current_pin_opens_nothing(self):
        for latest in ("1.0.0", "0.9.9", "1.0.0-rc.1"):
            with self.subTest(latest=latest):
                self.write("registry.json", {PACKAGE: packument(latest, {})})

                result = self.run_check()

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual([call["kind"] for call in self.calls()], ["curl"])
                self.assertIn(f"Current: {PACKAGE}@1.0.0; npm's latest is {latest}", result.stdout)

    def test_failed_lookup_fails_the_run_after_checking_the_other_packages(self):
        self.configure("missing@1.0.0", f"{PACKAGE}@1.0.0")
        for response in (None, "version not found: 1.0.0", {"dist-tags": []}, {"dist-tags": {"latest": "next"}}):
            with self.subTest(response=response):
                registry = {PACKAGE: packument("1.2.0", {})}
                if response is not None:
                    registry["missing"] = response
                self.write("registry.json", registry)

                result = self.run_check()

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("could not read missing's latest release from npm", result.stderr)
                create, = self.calls("create")
                self.assertEqual(create["title"], f"Review and bump the {PACKAGE} pin to 1.2.0")
                self.assertIn("failed 1 lookup(s)", result.stdout)

    def test_later_runs_update_the_open_issue_instead_of_duplicating_it(self):
        self.write("issues.json", [[
            {"number": 40, "state": "open", **BY_OWNER, "body": tracking_body("1.1.0")},
            {"number": 41, "state": "open", **BY_BOT, "body": tracking_body("1.1.0")},
            {"number": 30, "state": "open", **BY_BOT, "body": tracking_body("1.1.0", "@example/other")},
        ]])
        self.write("registry.json", {PACKAGE: packument("1.1.0", {})})

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call["kind"] for call in self.calls()], ["curl", "list"])
        self.assertIn(f"Already tracked: {PACKAGE}@1.1.0 in issue #40", result.stdout)

        self.write("registry.json", {PACKAGE: packument("1.3.0", {})})

        result = self.run_check()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        edit, = [call for call in self.calls() if call["kind"] not in ("curl", "list")]
        self.assertEqual(edit["kind"], "edit")
        self.assertEqual(edit["issue"], "40")
        self.assertEqual(edit["title"], f"Review and bump the {PACKAGE} pin to 1.3.0")
        self.assertIn("<!-- mcp-release-version:1.3.0 -->", edit["body"])
        self.assertIn("updated 1", result.stdout)

    def test_closed_issues_reopen_tracking_unless_that_release_was_declined(self):
        cases = (("completed", "1.1.0", "1.1.0", True), ("not_planned", "1.1.0", "1.1.0", False),
                 ("not_planned", "1.1.0", "1.2.0", True))
        for reason, declined, latest, creates in cases:
            with self.subTest(reason=reason, declined=declined, latest=latest):
                self.write("issues.json", [[
                    {"number": 50, "state": "closed", "state_reason": reason, **BY_BOT,
                     "body": tracking_body(declined)},
                ]])
                self.write("registry.json", {PACKAGE: packument(latest, {})})

                result = self.run_check()

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(self.calls("create")), int(creates))
                if not creates:
                    self.assertIn(f"Skipped: {PACKAGE}@{latest} was closed as not planned", result.stdout)

    def test_unpinned_or_differing_pins_fail_before_any_lookup(self):
        for mismatch in (PACKAGE, f"{PACKAGE}@latest", f"{PACKAGE}@1.0.1"):
            with self.subTest(mismatch=mismatch):
                codex = self.repo / ".codex/config.toml"
                codex.write_text(codex.read_text().replace(f"{PACKAGE}@1.0.0", mismatch))

                result = self.run_check()

                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(PACKAGE, result.stderr)
                self.assertEqual(self.calls(), [])
                self.configure(f"{PACKAGE}@1.0.0")


if __name__ == "__main__":
    unittest.main()
