"""Verify TestFlight orchestration without contacting Apple."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class TestFlightTests(unittest.TestCase):
    def run_lane(self, scenario="success", **env):
        settings = {**os.environ, "TESTFLIGHT_SCENARIO": scenario,
                    "PODHAVEN_TESTFLIGHT_NOTES": "Fixed playback", "ASC_KEY_PATH": "",
                    "ASC_KEY_ID": "", "ASC_ISSUER_ID": "", **env}
        if "PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS" not in env:
            settings.pop("PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS", None)
        result = subprocess.run(["ruby", str(ROOT / "bin/tests/testflight_fakes.rb"),
                                 str(ROOT / "fastlane/Fastfile")], env=settings,
                                text=True, capture_output=True, timeout=15)
        return result, json.loads(result.stdout)

    def test_waits_for_exact_build_submits_and_verifies_assignment(self):
        result, events = self.run_lane()
        self.assertEqual(result.returncode, 0, result.stderr)
        wait = next(event[1] for event in events if event[0] == "wait")
        self.assertEqual(wait["app_version"], "1.0.1")
        self.assertEqual(wait["build_version"], "569")
        self.assertEqual(wait["poll_interval"], 30)
        self.assertEqual(wait["timeout_duration"], 7200)
        self.assertFalse(wait["select_latest"])
        self.assertTrue(wait["wait_for_build_beta_detail_processing"])
        config = next(event[1] for event in events if event[0] == "distribute")
        self.assertEqual(config["groups"], ["everyone-id"])
        self.assertEqual(config["changelog"], "Fixed playback")
        self.assertTrue(config["submit_beta_review"])
        self.assertTrue(config["notify_external_testers"])
        self.assertFalse(config["expire_previous_builds"])
        self.assertIn(["groups", {"builds": "build-id"}], events)
        self.assertIn("waiting for beta review", events[-1][1])

    def test_processing_beyond_thirty_minutes_still_distributes_the_exact_build(self):
        result, events = self.run_lane("slow_processing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(event[0] == "wait" for event in events), 1)
        config = next(event[1] for event in events if event[0] == "distribute")
        self.assertEqual(config["app_version"], "1.0.1")
        self.assertEqual(config["build_number"], "569")
        self.assertIn("Confirmed 1.0.1 (569) in Everyone", events[-1][1])

    def test_timeout_reports_preserved_upload_and_retry_instead_of_a_crash(self):
        result, events = self.run_lane("slow_processing", PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS="1800")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("1.0.1 (569)", result.stderr)
        self.assertIn("1800 seconds", result.stderr)
        self.assertIn("upload is preserved", result.stderr)
        self.assertIn("same --notes", result.stderr)
        self.assertIn("Build Uploads", result.stderr)
        self.assertNotIn("BuildWatcher exceeded", result.stderr)
        self.assertFalse(any(event[0] in ("distribute", "expire", "success") for event in events))

    def test_processing_wait_accepts_a_longer_timeout(self):
        result, events = self.run_lane("slow_processing", PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS="14400")
        self.assertEqual(result.returncode, 0, result.stderr)
        wait = next(event[1] for event in events if event[0] == "wait")
        self.assertEqual(wait["timeout_duration"], 14400)

    def test_invalid_processing_timeout_fails_before_login(self):
        for value in ("", "0", "-1", "1.5", "forever"):
            with self.subTest(value=value):
                result, events = self.run_lane(PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("PODHAVEN_TESTFLIGHT_TIMEOUT_SECONDS", result.stderr)
                self.assertEqual(events, [])

    def test_unrelated_watcher_crashes_are_not_reported_as_processing_delays(self):
        result, events = self.run_lane("watcher_error")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.strip(), "Unexpected watcher failure")
        self.assertFalse(any(event[0] in ("distribute", "success") for event in events))

    def test_verification_accepts_assignment_on_a_later_page(self):
        result, events = self.run_lane("paginated")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Confirmed 1.0.1 (569) in Everyone", events[-1][1])

    def test_preflight_only_checks_login_and_external_group(self):
        result, events = self.run_lane(TESTFLIGHT_PREFLIGHT="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(event[0] in ("wait", "distribute") for event in events))

    def test_waiting_review_is_expired_and_verified_before_distribution(self):
        result, events = self.run_lane("waiting_review")
        self.assertEqual(result.returncode, 0, result.stderr)
        expire = events.index(["expire", "older-id"])
        distribute = next(i for i, event in enumerate(events) if event[0] == "distribute")
        reads = [i for i, event in enumerate(events) if event[0] == "readback" and event[1]["build_id"] == "older-id"]
        self.assertEqual(len(reads), 2)
        self.assertLess(reads[0], expire)
        self.assertLess(expire, reads[1])
        self.assertLess(reads[1], distribute)
        config = events[distribute][1]
        self.assertFalse(config["reject_build_waiting_for_review"])

    def test_preflight_leaves_waiting_review_until_replacement_is_valid(self):
        result, events = self.run_lane("waiting_review", TESTFLIGHT_PREFLIGHT="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(event[0] == "builds" for event in events))
        self.assertFalse(any(event[0] in ("expire", "distribute") for event in events))

    def test_prepare_cancels_waiting_review_before_an_upload_exists(self):
        result, events = self.run_lane("waiting_review", TESTFLIGHT_PREPARE="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["expire", "older-id"], events)
        self.assertFalse(any(event[0] in ("wait", "distribute") for event in events))

    def test_active_review_requests_next_patch_version(self):
        for preflight in ("true", "false"):
            with self.subTest(preflight=preflight), tempfile.TemporaryDirectory() as folder:
                result, events = self.run_lane("active_review", TESTFLIGHT_PREFLIGHT=preflight,
                                              PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH=str(Path(folder) / "next"))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(["next_version", "1.0.2"], events)
                self.assertFalse(any(event[0] in ("expire", "distribute", "success") for event in events))

    def test_review_starting_during_replacement_requests_new_version(self):
        with tempfile.TemporaryDirectory() as folder:
            result, events = self.run_lane("review_started", PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH=str(Path(folder) / "next"))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(["next_version", "1.0.2"], events)
            self.assertFalse(any(event[0] in ("expire", "distribute") for event in events))

    def test_apple_refusing_expiration_after_review_starts_requests_new_version(self):
        with tempfile.TemporaryDirectory() as folder:
            result, events = self.run_lane("expire_review_started", PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH=str(Path(folder) / "next"))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(["next_version", "1.0.2"], events)
            self.assertIn(["expire", "older-id"], events)
            self.assertFalse(any(event[0] in ("distribute", "success") for event in events))

    def test_apple_reporting_active_review_during_submission_requests_new_version(self):
        with tempfile.TemporaryDirectory() as folder:
            result, events = self.run_lane("submission_started", PODHAVEN_TESTFLIGHT_NEXT_VERSION_PATH=str(Path(folder) / "next"))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(["next_version", "1.0.2"], events)
            self.assertEqual(sum(event[0] == "distribute" for event in events), 1)
            self.assertFalse(any(event[0] in ("expire", "success") for event in events))

    def test_reuse_cannot_rebuild_an_active_review(self):
        result, events = self.run_lane("active_review")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without --reuse", result.stderr)
        self.assertIn("1.0.1 (568)", result.stderr)
        self.assertFalse(any(event[0] in ("expire", "distribute") for event in events))

    def test_unrelated_or_already_submitted_builds_are_not_expired(self):
        for scenario in ("target_in_review", "approved_previous", "expired_previous", "other_version", "other_platform"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(any(event[0] == "expire" for event in events))

    def test_unsafe_or_unconfirmed_replacement_stops_distribution(self):
        for scenario in ("newer_review", "multiple_reviews", "review_finished", "expire_error", "expire_unconfirmed"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[0] == "distribute" for event in events))
                if scenario in ("newer_review", "multiple_reviews", "review_finished"):
                    self.assertFalse(any(event[0] == "expire" for event in events))

    def test_submission_conflict_reports_retry_and_other_errors_propagate(self):
        result, events = self.run_lane("submission_conflict")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Retry", result.stderr)
        self.assertFalse(any(event[0] == "success" for event in events))
        result, _ = self.run_lane("submission_error")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Apple authentication failed", result.stderr)

    def test_invalid_groups_processing_or_builds_cannot_distribute(self):
        for scenario in ("missing_group", "duplicate_group", "internal_group", "timeout",
                         "wrong_build", "wrong_app", "wrong_platform", "invalid", "expired", "compliance"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[0] == "distribute" for event in events))

    def test_unconfirmed_assignment_or_rejection_is_failure(self):
        for scenario in ("unconfirmed", "rejected"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertNotEqual(result.returncode, 0)
                expected = "assignment to Everyone" if scenario == "unconfirmed" else "BETA_REJECTED"
                self.assertIn(expected, result.stderr)
                self.assertFalse(any(event[0] == "success" for event in events))

    def test_api_key_is_loaded_from_a_path(self):
        result, events = self.run_lane(ASC_KEY_PATH="/private/key.p8", ASC_KEY_ID="test-key",
                                       ASC_ISSUER_ID="test-issuer")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events[0], ["token", {"key_id": "test-key", "issuer_id": "test-issuer",
                                               "filepath": "/private/key.p8"}])

    def test_blank_or_oversized_notes_fail_before_login(self):
        for notes in ("  ", "a" * 4001):
            result, events = self.run_lane(PODHAVEN_TESTFLIGHT_NOTES=notes)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(events, [])


if __name__ == "__main__":
    unittest.main()
