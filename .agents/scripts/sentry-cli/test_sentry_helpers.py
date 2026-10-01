#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]


class SentryHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.call_log = self.root / "calls.jsonl"
        self.fake_sentry = self.root / "sentry"
        self.fake_sentry.write_text(
            """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["FAKE_SENTRY_CALL_LOG"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")

if args[:2] == ["auth", "status"]:
    raise SystemExit(int(os.environ.get("FAKE_SENTRY_AUTH_EXIT", "0")))

if args[:2] == ["issue", "view"]:
    project = os.environ.get("FAKE_SENTRY_PROJECT", "podhaven")
    print(json.dumps({
        "id": "123",
        "shortId": "PODHAVEN-ABC",
        "title": "Example failure",
        "status": "unresolved",
        "level": "error",
        "count": "3",
        "userCount": 2,
        "firstSeen": "2025-01-02T03:04:05Z",
        "lastSeen": "2025-01-03T03:04:05Z",
        "org": "artisanal-software",
        "project": {"slug": project},
    }))
    raise SystemExit(0)

if args[:2] == ["issue", "events"]:
    if os.environ.get("FAKE_SENTRY_EMPTY_EVENTS") == "1":
        print('{"data": []}')
    else:
        print(json.dumps({"data": [{
            "id": os.environ.get("FAKE_SENTRY_EVENT_ID", "event-1"),
            "dateCreated": "2025-01-03T03:04:05Z",
            "title": "Example failure",
            "entries": [{"type": "exception", "data": {"values": [{"type": "ExampleError", "value": "failed"}]}}],
            "tags": [],
        }]}))
    raise SystemExit(0)

if args and args[0] == "api":
    endpoint = args[1]
    if "/attachments/attachment-1/" in endpoint:
        sys.stdout.buffer.write(bytes.fromhex(os.environ["FAKE_SENTRY_RAW_HEX"]))
        raise SystemExit(0)
    if "/attachments/attachment-2/" in endpoint:
        print("escape")
        raise SystemExit(0)
    if endpoint.endswith("/attachments/"):
        body = [
            {"id": "attachment-1", "name": "log.ndjson", "size": 4},
            {"id": "attachment-2", "name": "../../escape.txt", "size": 6},
        ]
    elif "/tags/" in endpoint:
        body = [{"value": "example", "count": 3}]
    elif "/events/?" in endpoint:
        body = [{"id": os.environ.get("FAKE_SENTRY_EVENT_ID", "event-1"),
                 "tags": [{"key": "release", "value": "example-release"}],
                 "contexts": {"feedback": {"message": "Example feedback"}}}]
    elif endpoint.endswith("/activities/"):
        body = {"activity": [{"id": "activity-1", "type": "set_unresolved"}]}
    elif endpoint.endswith("/notes/"):
        body = [{"id": "note-1", "text": "Example note"}]
    else:
        raise SystemExit(f"unsupported fake API endpoint: {endpoint}")
    response = {"status": 200, "statusText": "OK", "body": body}
    if os.environ.get("FAKE_SENTRY_API_MATCH", "unlikely") in endpoint:
        mode = os.environ.get("FAKE_SENTRY_API_MODE")
        if mode == "empty":
            response["body"] = {"activity": []} if "/activities/" in endpoint else []
        elif mode == "http":
            response = {"status": 403, "statusText": "Forbidden", "body": {"detail": "denied"}}
        elif mode == "json":
            print("not json")
            raise SystemExit(0)
        elif mode == "type":
            response["body"] = "unexpected"
        elif mode == "row":
            response["body"] = ["unexpected"]
        elif mode == "fields":
            response["body"] = [{}]
        elif mode == "bare":
            response = body
        elif mode == "status":
            response["status"] = "200"
        elif mode == "missing_body":
            del response["body"]
        elif mode == "exit":
            print("synthetic CLI failure", file=sys.stderr)
            print(json.dumps(response))
            raise SystemExit(1)
    print(json.dumps(response))
    raise SystemExit(0)

if args and args[0] == "explore":
    print('{"data": [{"severity": "error", "message": "failed", "count()": 1}], "hasMore": false}')
    raise SystemExit(0)

if args[:2] == ["log", "list"]:
    print('{"data": [{"timestamp": "2025-01-03T03:04:05Z", "severity": "error", "message": "failed"}], "hasMore": false}')
    raise SystemExit(0)

print(f"unsupported fake sentry command: {args}", file=sys.stderr)
raise SystemExit(2)
"""
        )
        self.fake_sentry.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_script(
        self,
        name: str,
        *arguments: str,
        extra_environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "SENTRY_BIN": str(self.fake_sentry),
                "FAKE_SENTRY_CALL_LOG": str(self.call_log),
                "FAKE_SENTRY_RAW_HEX": b' {"message":"one"}\r\n{"message":"two"}\n'.hex(),
            }
        )
        if extra_environment:
            environment.update(extra_environment)
        return subprocess.run(
            ["bash", str(SCRIPT_DIR / name), *arguments],
            cwd=REPO_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def calls(self) -> list[list[str]]:
        return [json.loads(line) for line in self.call_log.read_text().splitlines()]

    def write_issue_json(self, project: str = "podhaven") -> Path:
        path = self.root / "issue.json"
        path.write_text(
            json.dumps(
                {
                    "org": "artisanal-software",
                    "project": {"slug": project},
                }
            )
        )
        return path

    def test_issue_fetch_uses_recorded_lifetime_and_writes_an_event(self) -> None:
        output = self.root / "issue-output"

        result = self.run_script(
            "fetch_issue_bundle.sh",
            "PODHAVEN-ABC",
            "--out",
            str(output),
            "--events",
            "2",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / "event_event-1.json").is_file())
        self.assertIn("environment: example (3)", result.stdout)
        self.assertIn("ExampleError: failed", result.stdout)
        self.assertEqual(json.loads((output / "tags_environment.json").read_text()),
                         [{"value": "example", "count": 3}])
        event_call = next(
            call for call in self.calls() if call[:2] == ["issue", "events"]
        )
        period_index = event_call.index("--period")
        self.assertEqual(event_call[period_index + 1], ">=2025-01-02T03:04:05Z")

    def test_issue_fetch_rejects_an_empty_event_result(self) -> None:
        result = self.run_script(
            "fetch_issue_bundle.sh",
            "PODHAVEN-ABC",
            "--out",
            str(self.root / "issue-output"),
            extra_environment={"FAKE_SENTRY_EMPTY_EVENTS": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No representative events", result.stderr)

    def test_issue_fetch_rejects_a_non_podhaven_issue(self) -> None:
        result = self.run_script(
            "fetch_issue_bundle.sh",
            "OTHER-ABC",
            "--out",
            str(self.root / "issue-output"),
            extra_environment={"FAKE_SENTRY_PROJECT": "other"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a PodHaven issue", result.stderr)
        self.assertFalse(any(call[:2] == ["issue", "events"] for call in self.calls()))

    def test_issue_fetch_rejects_a_nonempty_output_directory(self) -> None:
        output = self.root / "issue-output"
        output.mkdir()
        (output / "stale.json").write_text("{}")

        result = self.run_script(
            "fetch_issue_bundle.sh",
            "PODHAVEN-ABC",
            "--out",
            str(output),
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be empty", result.stderr)

    def test_issue_fetch_rejects_an_unsafe_event_id(self) -> None:
        result = self.run_script(
            "fetch_issue_bundle.sh",
            "PODHAVEN-ABC",
            "--out",
            str(self.root / "issue-output"),
            extra_environment={"FAKE_SENTRY_EVENT_ID": "../../escape"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsafe event ID", result.stderr)
        self.assertFalse((self.root / "escape.json").exists())

    def test_issue_fetch_passes_optional_span_depth(self) -> None:
        result = self.run_script(
            "fetch_issue_bundle.sh",
            "PODHAVEN-ABC",
            "--out",
            str(self.root / "issue-output"),
            "--spans",
            "all",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        view_call = next(call for call in self.calls() if call[:2] == ["issue", "view"])
        span_index = view_call.index("--spans")
        self.assertEqual(view_call[span_index + 1], "all")

    def test_attachment_command_lists_only_by_default(self) -> None:
        result = self.run_script(
            "download_event_attachments.sh",
            "--event",
            "event-1",
            "--issue-json",
            str(self.write_issue_json()),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        api_calls = [call for call in self.calls() if call and call[0] == "api"]
        self.assertEqual(len(api_calls), 1)
        self.assertIn("log.ndjson", result.stdout)
        self.assertIn("2 attachment(s)", result.stdout)

    def test_attachment_command_downloads_only_explicit_names(self) -> None:
        output = self.root / "attachments"
        result = self.run_script(
            "download_event_attachments.sh",
            "--event",
            "event-1",
            "--issue-json",
            str(self.write_issue_json()),
            "--dir",
            str(output),
            "--name",
            "log.ndjson",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((output / "log.ndjson").read_bytes(),
                         b' {"message":"one"}\r\n{"message":"two"}\n')
        self.assertEqual([path.name for path in output.iterdir()], ["log.ndjson"])

    def test_attachment_command_contains_hostile_filenames(self) -> None:
        output = self.root / "attachments"
        result = self.run_script(
            "download_event_attachments.sh",
            "--event",
            "event-1",
            "--issue-json",
            str(self.write_issue_json()),
            "--dir",
            str(output),
            "--all",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(output.is_dir(), result.stdout + result.stderr)
        self.assertFalse((self.root / "escape.txt").exists())
        self.assertEqual(
            sorted(path.name for path in output.iterdir()),
            ["attachment-2-escape.txt", "log.ndjson"],
        )

    def test_feedback_fetch_preserves_native_and_fallback_events(self) -> None:
        for fallback in (False, True):
            with self.subTest(fallback=fallback):
                output = self.root / f"feedback-{fallback}"
                result = self.run_script(
                    "fetch_feedback_bundle.sh", "podhaven:123", "--out", str(output),
                    extra_environment={"FAKE_SENTRY_EMPTY_EVENTS": str(int(fallback))},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Attachments: log.ndjson, ../../escape.txt", result.stdout)
                self.assertIn("Event: event-1", result.stdout)
                event = json.loads((output / "event_event-1.json").read_text())
                self.assertEqual(event["id"], "event-1")
                if fallback:
                    self.assertEqual(event["contexts"]["feedback"]["message"], "Example feedback")
                    self.assertIn("Release: example-release", result.stdout)
                self.assertEqual(json.loads((output / "activities.json").read_text()),
                                 {"activity": [{"id": "activity-1", "type": "set_unresolved"}]})
                self.assertEqual(json.loads((output / "notes.json").read_text()),
                                 [{"id": "note-1", "text": "Example note"}])

    def test_required_api_responses_fail_clearly(self) -> None:
        cases = (
            ("http", "HTTP 403"), ("json", "invalid JSON"),
            ("type", "expected"), ("row", "expected"),
            ("fields", "expected"), ("bare", "envelope"),
            ("status", "status"), ("missing_body", "body"), ("exit", "CLI"),
        )
        for target in ("attachments", "events"):
            for mode, diagnostic in cases:
                with self.subTest(target=target, mode=mode):
                    output = self.root / f"bad-{target}-{mode}"
                    environment = {"FAKE_SENTRY_API_MATCH": f"/{target}/",
                                   "FAKE_SENTRY_API_MODE": mode, "FAKE_SENTRY_EMPTY_EVENTS": "1"}
                    if target == "attachments":
                        result = self.run_script(
                            "download_event_attachments.sh", "--event", "event-1",
                            "--issue-json", str(self.write_issue_json()),
                            "--dir", str(output), "--all", extra_environment=environment)
                    else:
                        result = self.run_script(
                            "fetch_feedback_bundle.sh", "podhaven:123", "--out", str(output),
                            extra_environment=environment)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(diagnostic, result.stderr)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertNotIn("0 attachment(s)", result.stdout)
                    self.assertFalse((output / "log.ndjson").exists())
                    self.assertFalse((output / "event_event-1.json").exists())

    def test_optional_evidence_failure_is_unavailable_not_empty(self) -> None:
        for target, script, filename in (
            ("tags/environment", "fetch_issue_bundle.sh", "tags_environment.json"),
            ("activities", "fetch_feedback_bundle.sh", "activities.json"),
            ("notes", "fetch_feedback_bundle.sh", "notes.json"),
        ):
            for mode in ("http", "json", "type", "row", "exit"):
                with self.subTest(target=target, mode=mode):
                    output = self.root / f"optional-{filename}-{mode}"
                    result = self.run_script(
                        script, "123", "--out", str(output),
                        extra_environment={"FAKE_SENTRY_API_MATCH": f"/{target}/",
                                           "FAKE_SENTRY_API_MODE": mode})
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("unavailable", result.stderr)
                    self.assertIn("unavailable", result.stdout)
                    self.assertNotIn("Traceback", result.stderr)
                    self.assertFalse((output / filename).exists())

    def test_empty_api_lists_are_successful_evidence(self) -> None:
        for script, target, filename, expected in (
            ("fetch_issue_bundle.sh", "tags/environment", "tags_environment.json", []),
            ("fetch_feedback_bundle.sh", "activities", "activities.json", {"activity": []}),
            ("fetch_feedback_bundle.sh", "notes", "notes.json", []),
            ("fetch_feedback_bundle.sh", "attachments", "attachments.json", []),
        ):
            with self.subTest(target=target):
                output = self.root / filename
                result = self.run_script(
                    script, "123", "--out", str(output),
                    extra_environment={"FAKE_SENTRY_API_MATCH": f"/{target}/",
                                       "FAKE_SENTRY_API_MODE": "empty"})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads((output / filename).read_text()), expected)
                self.assertNotIn("unavailable", result.stdout + result.stderr)

        result = self.run_script(
            "download_event_attachments.sh", "--event", "event-1",
            "--issue-json", str(self.write_issue_json()),
            extra_environment={"FAKE_SENTRY_API_MATCH": "/attachments/", "FAKE_SENTRY_API_MODE": "empty"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0 attachment(s)", result.stdout)

    def test_feedback_fallback_rejects_no_events(self) -> None:
        result = self.run_script(
            "fetch_feedback_bundle.sh", "123", "--out", str(self.root / "feedback"),
            extra_environment={"FAKE_SENTRY_EMPTY_EVENTS": "1", "FAKE_SENTRY_API_MATCH": "/events/",
                               "FAKE_SENTRY_API_MODE": "empty"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No representative events", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_authentication_failure_stops_before_requests(self) -> None:
        result = self.run_script(
            "fetch_issue_bundle.sh", "123", "--out", str(self.root / "issue"),
            extra_environment={"FAKE_SENTRY_AUTH_EXIT": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("auth required", result.stderr)
        self.assertEqual(self.calls(), [["auth", "status"]])

    def test_structured_log_fetch_requires_an_explicit_output(self) -> None:
        output = self.root / "logs"
        result = self.run_script(
            "fetch_sentry_logs.sh",
            "6h",
            "--out",
            str(output),
            "--query",
            "severity:[warn,error]",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / "detail.json").is_file())
        self.assertTrue((output / "summary.json").is_file())

    def test_structured_log_fetch_rejects_a_missing_output(self) -> None:
        result = self.run_script("fetch_sentry_logs.sh", "6h")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--out DIR", result.stderr)

    def test_missing_cli_stops_without_a_download_fallback(self) -> None:
        environment = os.environ.copy()
        environment.pop("SENTRY_BIN", None)
        environment["PATH"] = "/usr/bin:/bin"
        result = subprocess.run(
            [
                "bash",
                str(SCRIPT_DIR / "fetch_issue_bundle.sh"),
                "PODHAVEN-ABC",
                "--out",
                str(self.root / "issue-output"),
            ],
            cwd=REPO_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sentry CLI is required", result.stderr)
        self.assertNotIn("npx", result.stderr)

    def test_structured_log_window_is_a_total_duration(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "filter_sentry_logs",
            SCRIPT_DIR / "filter_sentry_logs.py",
        )
        if spec is None or spec.loader is None:
            self.fail("Could not load filter_sentry_logs.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        center = 1_000_000
        rows = [
            {"timestamp_precise": str((center - 600_000) * 1_000_000)},
            {"timestamp_precise": str((center + 600_000) * 1_000_000)},
            {"timestamp_precise": str((center + 600_001) * 1_000_000)},
        ]

        filtered = module.filter_rows(rows, center, 1_200_000)

        self.assertEqual(filtered, rows[:2])


if __name__ == "__main__":
    unittest.main()
