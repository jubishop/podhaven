"""Verify TestFlight orchestration without contacting Apple."""

import json
import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


class TestFlightTests(unittest.TestCase):
    def run_lane(self, scenario="success", **env):
        settings = {**os.environ, "TESTFLIGHT_SCENARIO": scenario,
                    "PODHAVEN_TESTFLIGHT_NOTES": "Fixed playback", "ASC_KEY_PATH": "",
                    "ASC_KEY_ID": "", "ASC_ISSUER_ID": "", **env}
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
        self.assertEqual(wait["timeout_duration"], 1800)
        self.assertFalse(wait["select_latest"])
        self.assertTrue(wait["wait_for_build_beta_detail_processing"])
        config = next(event[1] for event in events if event[0] == "distribute")
        self.assertEqual(config["groups"], ["everyone-id"])
        self.assertEqual(config["changelog"], "Fixed playback")
        self.assertTrue(config["submit_beta_review"])
        self.assertTrue(config["notify_external_testers"])
        self.assertFalse(config["expire_previous_builds"])
        self.assertIn(["groups", {"builds": "build-id", "id": "everyone-id"}], events)
        self.assertIn("waiting for beta review", events[-1][1])

    def test_preflight_only_checks_login_and_external_group(self):
        result, events = self.run_lane(TESTFLIGHT_PREFLIGHT="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(event[0] in ("wait", "distribute") for event in events))

    def test_invalid_groups_processing_or_builds_cannot_distribute(self):
        for scenario in ("missing_group", "duplicate_group", "internal_group", "timeout",
                         "wrong_build", "invalid", "expired", "compliance"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(event[0] == "distribute" for event in events))

    def test_unconfirmed_assignment_or_rejection_is_failure(self):
        for scenario in ("unconfirmed", "rejected"):
            with self.subTest(scenario=scenario):
                result, events = self.run_lane(scenario)
                self.assertNotEqual(result.returncode, 0)
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
