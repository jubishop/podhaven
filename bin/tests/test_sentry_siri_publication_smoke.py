"""Check the Siri catalog publication smoke verifier against controlled log rows."""

import copy
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

import service_guard

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader(
    "siri_publication_smoke", str(ROOT / "bin/sentry-siri-publication-smoke"))
spec = importlib.util.spec_from_loader(loader.name, loader)
smoke = importlib.util.module_from_spec(spec)
loader.exec_module(smoke)

SOURCE = {"gitCommitHash": "abc1234"}
RUN = "0123456789abcdef"
ROW = {
    "sentry.item_id": "f" * 32,
    "message": "siriCatalogPublication trigger=launch publishMs=1262 fetchMs=4 writeMs=1258 "
               "podcasts=1 episodes=1 bytes=512 maxBytes=33554432 oversized=false "
               "openMs=37 appState=inactive suppressed=0",
    "severity": "warn",
    "category": "SiriCatalogPublication",
    "subsystem": "PodHaven",
    "version": "1.4.2",
    "buildNumber": "590",
    "gitCommitHash": "abc1234",
    "logSessionID": "E90F8D1A-9523-4F6D-95F5-FB62E9001F6C",
    "sentry.environment": "diagnostics-issue-737",
    "diagnostic-run": RUN,
}


class SiriPublicationSmokeTests(unittest.TestCase):
    def verify(self, rows):
        return smoke.verify(rows, SOURCE, RUN)

    def test_accepts_bounded_attributed_launch_summary(self):
        result = self.verify([ROW, dict(ROW, message="controlled session ready", severity="debug")])
        self.assertEqual(result["fields"]["writeMs"], "1258")
        self.assertEqual(result["sessionID"], ROW["logSessionID"])

    def test_rejects_private_metadata_in_any_run_log(self):
        leaked = dict(ROW, message="Private Sentinel Title", severity="warn")
        with self.assertRaisesRegex(AssertionError, "private media metadata"):
            self.verify([ROW, leaked])

    def test_rejects_missing_duplicate_or_mismatched_summaries(self):
        cases = [
            [],
            [ROW, copy.deepcopy(ROW)],
            [dict(ROW, gitCommitHash="other")],
            [dict(ROW, message=ROW["message"].replace("writeMs=1258", "writeMs=12"))],
            [dict(ROW, message=ROW["message"] + " title=Show")],
            [dict(ROW, message=ROW["message"].replace("trigger=launch", "trigger=commit"))],
        ]
        for rows in cases:
            with self.subTest(rows=rows), self.assertRaises(AssertionError):
                self.verify(rows)


if __name__ == "__main__":
    unittest.main()
