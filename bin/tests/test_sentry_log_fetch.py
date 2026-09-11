from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / ".agents/scripts/sentry-cli/fetch_sentry_logs.sh"
)


class SentryLogFetchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "output"
        self.calls = self.root / "calls.jsonl"
        self.fixture = self.root / "fixture.json"
        self.fake = self.root / "sentry"
        self.fake.write_text("""#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
with open(os.environ["FETCH_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if args == ["auth", "status"]:
    sys.exit(0)
fixture = json.loads(Path(os.environ["FETCH_TEST_FIXTURE"]).read_text())
if args[0] == "explore":
    cursor = args[args.index("--cursor") + 1] if "--cursor" in args else "first"
    payload = fixture["pages"][cursor]
else:
    assert args[:2] == ["log", "list"], args
    payload = fixture["detail"]
if isinstance(payload, int):
    print("Fixture request failed", file=sys.stderr)
    sys.exit(payload)
print(json.dumps(payload))
""")
        self.fake.chmod(0o755)

    def fetch(self, query=None, pages=None, detail=None, period="6h"):
        self.fixture.write_text(
            json.dumps(
                {
                    "pages": pages
                    if pages is not None
                    else {"first": {"data": [self.row("failed", 5)], "hasMore": False}},
                    "detail": detail
                    if detail is not None
                    else {"data": [], "hasMore": False},
                }
            )
        )
        arguments = ["bash", str(SCRIPT), period, "--out", str(self.output)]
        if query is not None:
            arguments += ["--query", query]
        return subprocess.run(
            arguments,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
            env={
                **os.environ,
                "SENTRY_BIN": str(self.fake),
                "FETCH_TEST_CALLS": str(self.calls),
                "FETCH_TEST_FIXTURE": str(self.fixture),
            },
        )

    @staticmethod
    def row(message, count):
        return {"severity": "error", "message": message, "count()": count}

    def requests(self):
        return [
            args
            for line in self.calls.read_text().splitlines()
            if (args := json.loads(line)) != ["auth", "status"]
        ]

    def read(self, filename):
        return json.loads((self.output / filename).read_text())

    def test_scope_filter_preserves_default_for_all_requests(self):
        query = "user.id:[one,two] trace:two"
        result = self.fetch(query=query)
        self.assertEqual(result.returncode, 0, result.stderr)
        for args in self.requests():
            self.assertEqual(
                args[args.index("--query") + 1], f"{query} severity:[warn,error]"
            )

    def test_quoted_message_does_not_select_severity(self):
        query = 'message:"severity:info"'
        result = self.fetch(query=query)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("severity:[warn,error]", self.read("coverage.json")["query"])

    def test_explicit_severity_is_preserved(self):
        query = "severity:[info,debug] user.id:one"
        result = self.fetch(query=query)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read("coverage.json")["query"], query)

    def test_all_aggregate_pages_share_a_fixed_window_with_detail(self):
        result = self.fetch(
            pages={
                "first": {
                    "data": [self.row("first", 5)],
                    "hasMore": True,
                    "nextCursor": "0:100:0",
                },
                "0:100:0": {"data": [self.row("second", 7)], "hasMore": False},
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = self.read("summary.json")
        self.assertEqual(summary["data"], [self.row("second", 7), self.row("first", 5)])
        self.assertFalse(summary["hasMore"])
        periods = {args[args.index("--period") + 1] for args in self.requests()}
        self.assertEqual(len(periods), 1)
        start, end = next(iter(periods)).split("..")
        self.assertEqual(
            datetime.fromisoformat(end) - datetime.fromisoformat(start),
            timedelta(hours=6),
        )
        coverage = self.read("coverage.json")
        self.assertEqual(coverage["summary"], "complete")
        self.assertEqual(coverage["counts_by_severity"], {"error": 12})

    def test_missing_cursor_reports_partial_counts_and_fails(self):
        result = self.fetch(
            pages={
                "first": {"data": [self.row("first", 5)], "hasMore": True},
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("coverage.json")["summary"], "partial")
        self.assertEqual(self.read("summary.json")["data"], [self.row("first", 5)])
        self.assertIn("cursor", result.stderr.lower())

    def test_repeated_cursor_cannot_loop_or_claim_completeness(self):
        result = self.fetch(
            pages={
                "first": {
                    "data": [self.row("first", 5)],
                    "hasMore": True,
                    "nextCursor": "repeat",
                },
                "repeat": {
                    "data": [self.row("second", 7)],
                    "hasMore": True,
                    "nextCursor": "repeat",
                },
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("coverage.json")["summary"], "partial")
        self.assertIn("cursor", result.stderr.lower())

    def test_failed_page_retains_partial_counts(self):
        result = self.fetch(
            pages={
                "first": {
                    "data": [self.row("first", 5)],
                    "hasMore": True,
                    "nextCursor": "next-page",
                },
                "next-page": 1,
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("coverage.json")["summary"], "partial")
        self.assertEqual(self.read("summary.json")["data"], [self.row("first", 5)])

    def test_missing_pagination_metadata_is_not_complete(self):
        result = self.fetch(pages={"first": {"data": [self.row("first", 5)]}})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("coverage.json")["summary"], "partial")

    def test_duplicate_groups_are_not_double_counted(self):
        result = self.fetch(
            pages={
                "first": {
                    "data": [self.row("first", 5)],
                    "hasMore": True,
                    "nextCursor": "next-page",
                },
                "next-page": {"data": [self.row("first", 5)], "hasMore": False},
            }
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read("coverage.json")["counts_by_severity"], {"error": 5})

    def test_detail_sample_does_not_reduce_aggregate_counts(self):
        result = self.fetch(detail={"data": [self.row("failed", 1)], "hasMore": True})
        self.assertEqual(result.returncode, 0, result.stderr)
        coverage = self.read("coverage.json")
        self.assertEqual(coverage["summary"], "complete")
        self.assertEqual(coverage["detail"], "sample")
        self.assertEqual(coverage["counts_by_severity"], {"error": 5})

    def test_failed_detail_retains_complete_summary_but_fails(self):
        result = self.fetch(detail=1)
        self.assertNotEqual(result.returncode, 0)
        coverage = self.read("coverage.json")
        self.assertEqual(coverage["summary"], "complete")
        self.assertEqual(coverage["detail"], "unavailable")


if __name__ == "__main__":
    unittest.main()
