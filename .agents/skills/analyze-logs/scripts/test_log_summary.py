#!/usr/bin/env python3

"""Unit tests for log_summary.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import log_summary as ls  # noqa: E402


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
