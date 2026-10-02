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
            "tags": [{"key": "diagnostic-run", "value": "run"}, {"key": "log-session-id", "value": "prior"},
                     {"key": "chart-probe-checkpoint", "value": "all-final-states"}],
            "contexts": {"recent_log_files": {"observationSessionID": "current"}},
        }
        metadata = {"sessionID": "prior", "gitCommitHash": "commit", "version": "1", "buildNumber": "1", "timestamp": 1}
        records, freshness = [], []
        for index in range(8):
            source = "download" if index < 4 or index == 7 else "playback" if index < 6 else "opml"
            revision = 241 if index < 4 else 13
            sequence = revision * 2
            numerator = 240 + index if index < 4 else 12
            denominator = 1_000_000_000 if index < 4 else 1_000_000
            instance = str(index)
            for offset in range(2):
                snapshot = {"source": source, "instance": instance, "revision": revision,
                            "sequence": sequence - 1 + offset, "timestamp": 1, "width": 12 if index % 2 == 0 else 28,
                            "height": 12 if index % 2 == 0 else 28, "numerator": numerator,
                            "denominator": denominator, "values": [numerator / denominator],
                            "sectorCount": 2 + offset if source == "opml" else 1,
                            "geometryObservation": "current_render", "transition": "disappeared" if index == 7 else "render",
                            "innerRadiusRatio": 0.4, "angularInset": 2}
                records.append(dict(metadata, kind="snapshot", metadata={"chart": json.dumps(snapshot)}))
            freshness.append({"instance": instance, "source": source, "latestSequence": sequence,
                              "latestRevision": revision, "latestTimestamp": 1, "omittedTransitions": sequence - 2})
        summary = dict(metadata, kind="retention", invalidRecords=0, instanceCapacity=32, historyCapacity=8,
                       sessionCapacity=4, mappedBytes=151552, evictions=0, omittedEvictionDetails=0, instances=freshness)
        return event, self.encode([summary] + records)

    @staticmethod
    def encode(records):
        return b"".join(json.dumps(row).encode() + b"\n" for row in records)

    def test_requires_previous_session_and_downloaded_evidence(self):
        event, data = self.fixture()
        result = probe.verify(event, data, len(data), {"gitCommitHash": "commit"}, "run")
        self.assertEqual(result["incidentSnapshots"], 16)
        self.assertEqual(result["activeFinalStates"], 7)
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

    def test_rejects_stale_missing_mixed_or_corrupt_instance_evidence(self):
        event, data = self.fixture()
        original = [json.loads(line) for line in data.splitlines()]
        variants = []
        stale = json.loads(data.splitlines()[12])
        snapshot = json.loads(stale["metadata"]["chart"])
        snapshot["numerator"] = 11
        stale["metadata"]["chart"] = json.dumps(snapshot)
        variants.append(original[:12] + [stale] + original[13:])
        variants.append(original[:1] + original[3:])
        mixed = dict(original[-1], sessionID="current")
        variants.append(original + [mixed])
        variants.append([dict(original[0], invalidRecords=1)] + original[1:])
        for records in variants:
            with self.subTest(records=len(records)):
                invalid = self.encode(records)
                with self.assertRaises(AssertionError):
                    probe.verify(event, invalid, len(invalid), {"gitCommitHash": "commit"}, "run")

    def test_rejects_uncontrolled_render_trap(self):
        event, data = self.fixture()
        event["tags"] = event["tags"][:-1]
        with self.assertRaises(AssertionError):
            probe.verify(event, data, len(data), {"gitCommitHash": "commit"}, "run")


if __name__ == "__main__":
    unittest.main()
