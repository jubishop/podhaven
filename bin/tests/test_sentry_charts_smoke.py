"""Validate the native chart probe's remote evidence gate."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = SourceFileLoader("charts_smoke", str(ROOT / "bin/sentry-charts-smoke"))
probe = module_from_spec(spec_from_loader(loader.name, loader))
loader.exec_module(probe)


class ChartProbeTests(unittest.TestCase):
    def test_api_unwraps_current_cli_response_and_rejects_failures(self):
        with patch.object(probe, "command", return_value=json.dumps({"status": 200, "body": [{"name": "chart-progress.ndjson"}]})):
            self.assertEqual(probe.api("test/"), [{"name": "chart-progress.ndjson"}])
        with patch.object(probe, "command", return_value=json.dumps({"status": 403, "body": {"detail": "denied"}})):
            with self.assertRaises(RuntimeError):
                probe.api("test/")

    def fixture(self):
        event = {
            "entries": [{"type": "exception", "data": {"values": [{"mechanism": {"handled": False, "type": "mach"}}]}}],
            "tags": [{"key": "diagnostic-run", "value": "run"}, {"key": "log-session-id", "value": "prior"}],
            "contexts": {"recent_log_files": {"observationSessionID": "current"}},
        }
        records = []
        for source, width, count in [("playback", 12, 1), ("download", 28, 1), ("opml", 12, 2), ("opml", 28, 3)]:
            records.append({"sessionID": "prior", "gitCommitHash": "commit", "version": "1", "buildNumber": "1", "timestamp": 1,
                            "metadata": {"chart": json.dumps({"source": source, "width": width, "height": width,
                                                              "numerator": 75, "denominator": 100, "sectorCount": count,
                                                              "innerRadiusRatio": 0.4, "angularInset": 2})}})
        data = b"".join(json.dumps(row).encode() + b"\n" for row in records)
        return event, data

    def test_requires_previous_session_and_downloaded_evidence(self):
        event, data = self.fixture()
        result = probe.verify(event, data, len(data), {"gitCommitHash": "commit"}, "run")
        self.assertEqual(result["incidentSnapshots"], 4)
        event["contexts"]["recent_log_files"]["observationSessionID"] = "prior"
        with self.assertRaises(AssertionError):
            probe.verify(event, data, len(data), {"gitCommitHash": "commit"}, "run")

    def test_rejects_wrong_bytes_commit_and_handled_events(self):
        event, data = self.fixture()
        for size, commit in [(len(data) - 1, "commit"), (len(data), "wrong")]:
            with self.assertRaises(AssertionError):
                probe.verify(event, data, size, {"gitCommitHash": commit}, "run")
        event["entries"][0]["data"]["values"][0]["mechanism"]["handled"] = True
        with self.assertRaises(AssertionError):
            probe.verify(event, data, len(data), {"gitCommitHash": "commit"}, "run")


if __name__ == "__main__":
    unittest.main()
