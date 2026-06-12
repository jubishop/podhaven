#!/usr/bin/env python3

"""Unit tests for symbolicate_metrickit.py."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import symbolicate_metrickit as sm  # noqa: E402


SAMPLE_PAYLOAD = {
    "callStackTree": {
        "callStackPerThread": False,
        "callStacks": [
            {
                "threadAttributed": True,
                "callStackPerThread": False,
                "callStackRootFrames": [
                    {
                        "binaryUUID": "ABCDEF12-3456-7890-ABCD-EF1234567890",
                        "offsetIntoBinaryTextSegment": 1024,
                        "binaryName": "PodHaven",
                        "sampleCount": 1,
                        "subFrames": [
                            {
                                "binaryUUID": "ABCDEF12-3456-7890-ABCD-EF1234567890",
                                "offsetIntoBinaryTextSegment": 2048,
                                "binaryName": "PodHaven",
                                "subFrames": [],
                            },
                            {
                                "binaryUUID": "11111111-2222-3333-4444-555555555555",
                                "offsetIntoBinaryTextSegment": 4096,
                                "binaryName": "libobjc.A.dylib",
                            },
                        ],
                    }
                ],
            },
            {
                "threadAttributed": False,
                "callStackPerThread": True,
                "callStackRootFrames": [],
            },
        ],
    },
    "diagnosticMetaData": {
        "platformArchitecture": "arm64e",
        "osVersion": "iPhone OS 18.0 (22A123)",
        "appVersion": "1.0",
        "appBuildVersion": "498",
    },
}


def write_log(tmp_path: Path, *entries: dict) -> Path:
    log = tmp_path / "log.ndjson"
    with log.open("w", encoding="utf-8") as f:
        for entry in entries:
            f.write(json.dumps(entry) + "\n")
    return log


class TestDetection(unittest.TestCase):
    def test_iter_metrickit_entries_filters_non_metrickit(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            log = write_log(
                tmp_path,
                {"level": 3, "timestamp": 100, "message": "boring"},
                {
                    "level": 3,
                    "timestamp": 200,
                    "message": "MetricKit crash diagnostic received",
                    "metadata": {"metricKitDiagnostic": json.dumps(SAMPLE_PAYLOAD)},
                },
                {
                    "level": 3,
                    "timestamp": 300,
                    "message": "MetricKit hang diagnostic received",
                    "metadata": {"metricKitDiagnostic": "{not valid json"},
                },
                {
                    "level": 3,
                    "timestamp": 400,
                    "message": "MetricKit appLaunch diagnostic received",
                    "metadata": {"metricKitDiagnostic": json.dumps(SAMPLE_PAYLOAD)},
                },
            )
            entries = list(sm.iter_metrickit_entries(log))
            self.assertEqual([e.timestamp_ms for e in entries], [200, 400])
            self.assertEqual([e.category for e in entries], ["crash", "appLaunch"])


class TestFlattening(unittest.TestCase):
    def test_flatten_frames_walks_subframes(self) -> None:
        stacks = sm.extract_call_stacks(SAMPLE_PAYLOAD)
        self.assertEqual(len(stacks), 2)
        first = stacks[0]
        self.assertTrue(first.thread_attributed)
        depths = [f.depth for f in first.frames]
        self.assertEqual(depths, [0, 1, 1])
        offsets = [f.offset for f in first.frames]
        self.assertEqual(offsets, [1024, 2048, 4096])
        uuids = [f.binary_uuid for f in first.frames]
        self.assertEqual(
            uuids,
            [
                "ABCDEF12-3456-7890-ABCD-EF1234567890",
                "ABCDEF12-3456-7890-ABCD-EF1234567890",
                "11111111-2222-3333-4444-555555555555",
            ],
        )
        self.assertEqual(stacks[1].frames, [])

    def test_group_frames_by_uuid_normalizes_case(self) -> None:
        stacks = sm.extract_call_stacks(SAMPLE_PAYLOAD)
        grouped = sm.group_frames_by_uuid(stacks)
        self.assertEqual(set(grouped), {
            "abcdef12-3456-7890-abcd-ef1234567890",
            "11111111-2222-3333-4444-555555555555",
        })
        # Two frames share the PodHaven UUID; both should be grouped together.
        self.assertEqual(len(grouped["abcdef12-3456-7890-abcd-ef1234567890"]), 2)


class TestAtosInvocation(unittest.TestCase):
    def test_offsets_are_passed_as_hex_with_prefix(self) -> None:
        # atos interprets bare numeric inputs as hex, so passing a decimal
        # `1689452` would silently look up `0x1689452` (the wrong address).
        # The script must hex-format offsets with an explicit `0x` prefix.
        from unittest.mock import MagicMock, patch

        result = MagicMock(returncode=0, stdout="sym1\nsym2\n")
        run_mock = MagicMock(return_value=result)
        with patch.object(sm.subprocess, "run", run_mock):
            sm.run_atos(Path("/tmp/fake"), "arm64", [56456, 1689452])

        cmd = list(run_mock.call_args.args[0])
        self.assertIn("-offset", cmd)
        self.assertIn("0xdc88", cmd)
        self.assertIn("0x19c76c", cmd)
        self.assertNotIn("56456", cmd)
        self.assertNotIn("1689452", cmd)


class TestAtosParsing(unittest.TestCase):
    def test_parses_one_line_per_frame(self) -> None:
        stdout = (
            "-[Foo bar] (in PodHaven) (Foo.swift:10)\n"
            "Baz.qux() (in PodHaven) (Baz.swift:42)\n"
        )
        self.assertEqual(
            sm.parse_atos_output(stdout, expected=2),
            [
                "-[Foo bar] (in PodHaven) (Foo.swift:10)",
                "Baz.qux() (in PodHaven) (Baz.swift:42)",
            ],
        )

    def test_pads_when_atos_returns_too_few_lines(self) -> None:
        result = sm.parse_atos_output("only line\n", expected=3)
        self.assertEqual(result, ["only line", None, None])

    def test_truncates_when_atos_returns_too_many_lines(self) -> None:
        result = sm.parse_atos_output("a\nb\nc\nd\n", expected=2)
        self.assertEqual(result, ["a", "b"])


class TestRendering(unittest.TestCase):
    def test_render_entry_text_shows_unresolved_frames(self) -> None:
        entry = sm.MetricKitEntry(
            line_number=42,
            timestamp_ms=1714000000000,
            category="crash",
            message="MetricKit crash diagnostic received",
            payload=SAMPLE_PAYLOAD,
        )
        symbolicated = sm.symbolicate_entry(entry, resolver=None)
        text = sm.render_entry_text(symbolicated)
        self.assertIn("crash diagnostic", text)
        self.assertIn("arm64e", text)
        self.assertIn("PodHaven+1024", text)
        self.assertIn("<unresolved>", text)
        self.assertIn("Unresolved binaries", text)

    def test_serialize_entry_round_trips_through_json(self) -> None:
        entry = sm.MetricKitEntry(
            line_number=1,
            timestamp_ms=1714000000000,
            category="crash",
            message="MetricKit crash diagnostic received",
            payload=SAMPLE_PAYLOAD,
        )
        symbolicated = sm.symbolicate_entry(entry, resolver=None)
        data = sm.serialize_entry(symbolicated)
        encoded = json.dumps(data)
        decoded = json.loads(encoded)
        self.assertEqual(decoded["category"], "crash")
        self.assertEqual(decoded["architecture"], "arm64e")
        self.assertEqual(len(decoded["callStacks"]), 2)
        self.assertEqual(decoded["callStacks"][0]["frames"][0]["offsetIntoBinaryTextSegment"], 1024)


def metrickit_entry(timestamp_ms: int, category: str = "crash") -> dict:
    return {
        "level": 3,
        "timestamp": timestamp_ms,
        "message": f"MetricKit {category} diagnostic received",
        "metadata": {"metricKitDiagnostic": json.dumps(SAMPLE_PAYLOAD)},
    }


class TestEmptyWindowReporting(unittest.TestCase):
    def _run_main(self, argv: list[str]) -> tuple[int, str]:
        import contextlib
        import io
        from unittest.mock import patch

        stdout = io.StringIO()
        with patch.object(sys, "argv", ["symbolicate_metrickit.py", *argv]):
            with contextlib.redirect_stdout(stdout):
                code = sm.main()
        return code, stdout.getvalue()

    def test_text_output_lists_entries_outside_window(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            log = write_log(tmp_path, metrickit_entry(100), metrickit_entry(200))
            code, out = self._run_main([
                str(log),
                "--around", "500000",
                "--window-ms", "1000",
                "--offline",
                "--cache-dir", str(tmp_path / "cache"),
            ])
        self.assertEqual(code, 0)
        self.assertIn("No MetricKit entries matched", out)
        self.assertIn("2 matching-category entries fall outside the --around window:", out)
        self.assertIn("epoch-ms 100", out)
        self.assertIn("epoch-ms 200", out)

    def test_text_output_counts_category_exclusions(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            log = write_log(tmp_path, metrickit_entry(100), metrickit_entry(200))
            code, out = self._run_main([
                str(log),
                "--category", "hang",
                "--offline",
                "--cache-dir", str(tmp_path / "cache"),
            ])
        self.assertEqual(code, 0)
        self.assertIn("No MetricKit entries matched", out)
        self.assertIn("2 entries excluded by --category.", out)

    def test_json_output_includes_outside_window(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            log = write_log(tmp_path, metrickit_entry(100), metrickit_entry(200))
            code, out = self._run_main([
                str(log),
                "--around", "500000",
                "--window-ms", "1000",
                "--offline",
                "--json",
                "--cache-dir", str(tmp_path / "cache"),
            ])
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["entries"], [])
        self.assertEqual(payload["excluded_by_category"], 0)
        self.assertEqual(
            [(e["timestamp_ms"], e["category"]) for e in payload["outside_window"]],
            [(100, "crash"), (200, "crash")],
        )


class TestUUIDNormalization(unittest.TestCase):
    def test_normalize_uuid_lowercases(self) -> None:
        self.assertEqual(
            sm.normalize_uuid("ABCDEF12-3456-7890-ABCD-EF1234567890"),
            "abcdef12-3456-7890-abcd-ef1234567890",
        )


if __name__ == "__main__":
    unittest.main()
