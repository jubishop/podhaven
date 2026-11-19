#!/usr/bin/env python3

"""Unit tests for log_summary.py."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.append(str(SCRIPT_DIR.parents[3] / "bin/tests"))

import log_summary as ls  # noqa: E402
import service_guard  # noqa: E402

LAUNCH = {"subsystem": "PodHaven", "category": "AppLauncher", "message": "launching"}
SESSION_A = "11111111-1111-1111-1111-111111111111"
SESSION_B = "22222222-2222-2222-2222-222222222222"


def entry(timestamp: int, session: str | None = None, commit: str = "aaaa111", **fields: Any) -> dict[str, Any]:
    record: dict[str, Any] = {
        "level": 1,
        "levelName": "debug",
        "timestamp": timestamp,
        "subsystem": "Feed",
        "category": "refresh",
        "message": "tick",
        "metadata": None,
        "source": "PodHaven",
        "file": "Feed.swift",
        "function": "refresh()",
        "line": 10,
    }
    if session is not None:
        record |= {"sessionID": session, "version": "2.1.1", "buildNumber": "500", "gitCommitHash": commit}
    return record | fields


class CLITestCase(unittest.TestCase):
    def write_log(self, *entries: dict[str, Any]) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "log.ndjson"
        path.write_text("".join(json.dumps(record) + "\n" for record in entries), encoding="utf-8")
        return path

    def run_cli(self, path: Path, *args: str) -> str:
        stdout = io.StringIO()
        with patch.object(sys, "argv", ["log_summary.py", str(path), *args]), contextlib.redirect_stdout(stdout):
            self.assertEqual(ls.main(), 0)
        return stdout.getvalue()

    def sessions(self, path: Path) -> list[dict[str, Any]]:
        return json.loads(self.run_cli(path, "--sessions", "--json"))["sessions"]


class TestSessions(CLITestCase):
    def test_each_session_id_is_its_own_session_with_its_build(self) -> None:
        path = self.write_log(
            entry(1_000, SESSION_A, **LAUNCH),
            entry(1_500, SESSION_A),
            entry(2_000, SESSION_B, commit="bbbb222", **LAUNCH),
            entry(2_500, SESSION_B, commit="bbbb222"),
        )

        sessions = self.sessions(path)

        self.assertEqual(
            [(s["session_id"], s["version"], s["build_number"], s["git_commit_hash"], s["entry_count"])
             for s in sessions],
            [(SESSION_A, "2.1.1", "500", "aaaa111", 2), (SESSION_B, "2.1.1", "500", "bbbb222", 2)],
        )
        listing = self.run_cli(path, "--sessions")
        self.assertIn(SESSION_B, listing)
        self.assertIn("2.1.1 (500) bbbb222", listing)

    def test_widget_sessions_without_launch_messages_scope_with_session(self) -> None:
        widget = {"source": "PodHavenWidget", "subsystem": "Widget"}
        path = self.write_log(
            entry(1_000, SESSION_A, **widget),
            entry(1_100, SESSION_A, **widget),
            entry(1_200, SESSION_A, **widget),
            entry(90_000, SESSION_B, **widget),
            entry(90_100, SESSION_B, **widget),
        )

        self.assertEqual([s["entry_count"] for s in self.sessions(path)], [3, 2])
        scoped = json.loads(self.run_cli(path, "--session", "2", "--json"))["primary"]
        self.assertEqual(scoped["active_entries"], 2)

    def test_entries_without_session_id_use_launch_messages(self) -> None:
        path = self.write_log(
            entry(1_000, **LAUNCH),
            entry(1_500),
            entry(60_000, **LAUNCH),
            entry(60_500),
            entry(120_000, SESSION_A),
            entry(120_500, SESSION_A),
        )

        self.assertEqual(
            [(s["session_id"], s["entry_count"]) for s in self.sessions(path)],
            [(None, 2), (None, 2), (SESSION_A, 2)],
        )

    def test_compare_other_scopes_to_the_primary_sessions_time_range(self) -> None:
        widget = {"source": "PodHavenWidget", "subsystem": "Widget"}
        app_log = self.write_log(
            entry(1_000, SESSION_A, **LAUNCH),
            entry(2_000, SESSION_A),
            entry(100_000, SESSION_B, **LAUNCH),
            entry(101_000, SESSION_B),
        )
        widget_log = self.write_log(
            entry(500, "widget-1", **widget),
            entry(1_500, "widget-2", **widget),
            entry(50_000, "widget-3", **widget),
            entry(100_500, "widget-4", **widget),
        )

        report = json.loads(self.run_cli(app_log, "--session", "2", "--compare-other", str(widget_log), "--json"))

        secondary = report["comparison"]["secondary"]
        self.assertEqual(secondary["active_entries"], 1)
        self.assertEqual(secondary["active_range"]["start_ms"], 100_500)


class TestMatch(CLITestCase):
    def test_match_finds_session_id_and_commit(self) -> None:
        path = self.write_log(
            entry(1_000, SESSION_A),
            entry(2_000, SESSION_B, commit="bbbb222"),
            entry(3_000, SESSION_B, commit="bbbb222"),
        )

        def match_count(needle: str) -> int:
            return json.loads(self.run_cli(path, "--match", needle, "--json"))["primary"]["selection"]["entry_count"]

        self.assertEqual(match_count(SESSION_A), 1)
        self.assertEqual(match_count("bbbb222"), 2)


class TestParseTimeArg(unittest.TestCase):
    def test_iso_with_utc_suffix(self) -> None:
        self.assertEqual(ls.parse_time_arg("2026-06-12T16:26:55Z"), 1781281615000)

    def test_iso_with_utc_offset(self) -> None:
        self.assertEqual(ls.parse_time_arg("2026-06-12T16:26:55+02:00"), 1781274415000)

    def test_naive_iso_is_pacific(self) -> None:
        # June dates fall in PDT (UTC-7), seven hours behind the Z-suffix case.
        self.assertEqual(ls.parse_time_arg("2026-06-12T16:26:55"), 1781306815000)

    def test_epoch_ms_passes_through(self) -> None:
        self.assertEqual(ls.parse_time_arg("1768679500000"), 1768679500000)

    def test_legacy_datetime_string_is_pacific(self) -> None:
        self.assertEqual(ls.parse_time_arg("2026-06-12 16:26"), 1781306760000)

    def test_unparseable_time_exits(self) -> None:
        import contextlib
        import io

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                ls.parse_time_arg("not a time")
        self.assertIn("cannot parse time", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
