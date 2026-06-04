#!/usr/bin/env python3

"""Unit tests for locate_logs.py."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import locate_logs  # noqa: E402


class TestSimulatorLookup(unittest.TestCase):
    def test_widget_log_uses_specific_app_group_container(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            completed = subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout=f"{tmp}\n",
                stderr="",
            )
            with patch.object(locate_logs.subprocess, "run", return_value=completed) as run_mock:
                candidates = locate_logs.widget_log_candidates(variant="dev")

        self.assertEqual(
            run_mock.call_args.args[0],
            [
                "xcrun",
                "simctl",
                "get_app_container",
                "booted",
                locate_logs.DEV_APP_BUNDLE,
                locate_logs.DEV_APP_GROUP,
            ],
        )
        self.assertEqual(candidates[0].path, Path(tmp) / "widget-log.ndjson")


if __name__ == "__main__":
    unittest.main()
