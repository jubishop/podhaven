"""Verify App Store metadata and submission behavior with fake Apple resources."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AppStoreReleaseTests(unittest.TestCase):
    def run_release(self, scenario="new", **env):
        environment = {**os.environ, "APPSTORE_SCENARIO": scenario, "PODHAVEN_APPSTORE_NOTES": "Fixed playback",
                       "ASC_KEY_PATH": "", "ASC_KEY_ID": "", "ASC_ISSUER_ID": "", **env}
        if "APPSTORE_BUILD" not in env:
            environment.pop("APPSTORE_BUILD", None)
        result = subprocess.run(["ruby", str(ROOT / "bin/tests/appstore_fakes.rb"),
                                 str(ROOT / "fastlane/appstore.rb")], env=environment,
                                text=True, capture_output=True, timeout=10)
        return result, json.loads(result.stdout)

    def writes(self, events):
        return [event for event in events if event[0].startswith("write_")]

    def test_status_is_read_only(self):
        result, events = self.run_release("status", APPSTORE_MODE="status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.writes(events))
        self.assertTrue(any("Live App Store version: 1.0" in str(event) for event in events))
        self.assertTrue(any("570: PROCESSING" in str(event) for event in events))

    def test_notes_use_latest_ios_testflight_build_and_primary_locale(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "notes.txt"
            result, events = self.run_release("notes_latest", APPSTORE_MODE="notes",
                                             PODHAVEN_APPSTORE_NOTES="", PODHAVEN_APPSTORE_NOTES_PATH=str(path))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(path.read_text(), "TestFlight notes\nExact text")
        self.assertIn(["beta_notes", "build-598"], events)
        self.assertFalse(self.writes(events))
        self.assertFalse(any(event[0] in ("wait", "versions", "reviews") for event in events))
        query = next(event[1] for event in events if event[0] == "builds")
        self.assertEqual(query["sort"], "-uploadedDate")
        self.assertNotIn("version", query)

    def test_missing_or_unusable_notes_do_not_fall_back_to_older_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "notes.txt"
            for scenario in ("notes_no_testflight", "notes_missing", "notes_blank", "notes_long",
                             "notes_unknown_locale", "notes_api_failure"):
                with self.subTest(scenario=scenario):
                    result, events = self.run_release(scenario, APPSTORE_MODE="notes",
                                                     PODHAVEN_APPSTORE_NOTES_PATH=str(path))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(path.exists())
                    self.assertFalse(self.writes(events))
                    self.assertNotIn(["beta_notes", "build-597"], events)

    def test_exact_build_creates_version_and_submits_automatically(self):
        result, events = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["write_create_version", "app-id", {"versionString": "1.1", "platform": "IOS",
                                                         "releaseType": "AFTER_APPROVAL"}], events)
        self.assertIn(["write_build", "build-569"], events)
        self.assertEqual(sum(event[0] == "write_notes" for event in events), 2)
        self.assertEqual(sum(event[0] == "write_submit" for event in events), 1)
        self.assertIn("WAITING_FOR_REVIEW", events[-1][1])

    def test_explicit_build_and_existing_version_are_used(self):
        result, events = self.run_release("existing", APPSTORE_BUILD="568")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["write_build", "build-568"], events)
        self.assertIn(["write_release_type", {"releaseType": "AFTER_APPROVAL"}], events)
        self.assertFalse(any(event[0] == "write_create_version" for event in events))

    def test_unusable_builds_and_conflicts_stop_before_writes(self):
        for scenario in ("no_build", "timeout", "expired", "internal_only", "compliance",
                         "wrong_version", "wrong_app", "wrong_build", "conflicting_version", "draft_other_items"):
            with self.subTest(scenario=scenario):
                result, events = self.run_release(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.writes(events))

    def test_waits_for_exact_processing_build_instead_of_submitting_an_older_build(self):
        result, events = self.run_release(APPSTORE_BUILD="570")
        self.assertEqual(result.returncode, 0, result.stderr)
        wait = next(event[1] for event in events if event[0] == "wait")
        self.assertEqual(wait["app_version"], "1.1")
        self.assertEqual(wait["build_version"], "570")
        self.assertEqual(wait["poll_interval"], 30)
        self.assertEqual(wait["timeout_duration"], 1800)
        self.assertFalse(wait["select_latest"])
        self.assertIn(["write_build", "build-570"], events)
        self.assertNotIn(["write_build", "build-569"], events)

    def test_submission_requires_an_exact_build(self):
        result, events = self.run_release(APPSTORE_BUILD="")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.writes(events))

    def test_preflight_checks_apple_without_needing_an_uploaded_build(self):
        result, events = self.run_release("no_build", APPSTORE_MODE="preflight", APPSTORE_BUILD="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.writes(events))
        self.assertFalse(any(event[0] in ("wait", "builds") for event in events))

    def test_preflight_rejects_pending_conflicts_and_already_released_versions(self):
        for scenario in ("conflicting_version", "draft_other_items", "already_submitted"):
            result, events = self.run_release(scenario, APPSTORE_MODE="preflight", APPSTORE_BUILD="")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.writes(events))

    def test_apple_must_confirm_build_notes_and_automatic_release(self):
        for scenario in ("build_not_saved", "notes_not_saved", "release_not_saved"):
            with self.subTest(scenario=scenario):
                result, events = self.run_release(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[0] == "write_submit" for event in events))

    def test_already_queued_submission_is_read_only(self):
        result, events = self.run_release("already_submitted")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.writes(events))
        self.assertIn("Already submitted", events[-1][1])

    def test_queued_submission_cannot_be_silently_replaced(self):
        for scenario in ("queued_different_build", "queued_different_notes"):
            result, events = self.run_release(scenario)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.writes(events))

    def test_retry_reuses_existing_draft_item(self):
        result, events = self.run_release("draft_resume")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(events), [["write_submit"]])

    def test_lost_response_does_not_create_duplicate_submission(self):
        result, events = self.run_release("response_lost")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ("write_create_version", "write_create_review", "write_review_item", "write_submit"):
            self.assertEqual(sum(event[0] == name for event in events), 1)

    def test_unconfirmed_submission_times_out_with_a_failure(self):
        result, events = self.run_release("unconfirmed")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sum(event[0] == "sleep" for event in events), 11)
        self.assertFalse(any(event[0] == "success" for event in events))


if __name__ == "__main__":
    unittest.main()
