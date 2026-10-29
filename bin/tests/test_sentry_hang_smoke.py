"""Validate the recovered-hang smoke's Sentry API and evidence helpers."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import service_guard

ROOT = Path(__file__).resolve().parents[2]
loader = SourceFileLoader("hang_smoke", str(ROOT / "bin/sentry-hang-smoke"))
smoke = module_from_spec(spec_from_loader(loader.name, loader))
loader.exec_module(smoke)


class HangSmokeTests(unittest.TestCase):
    def test_api_unwraps_current_cli_response_and_rejects_failures(self):
        response = {"status": 200, "statusText": "OK", "body": {"entries": []}}
        with patch.object(smoke, "command", return_value=json.dumps(response)):
            self.assertEqual(smoke.api("test/"), {"entries": []})
        response = {"status": 403, "statusText": "Forbidden", "body": {"detail": "denied"}}
        with patch.object(smoke, "command", return_value=json.dumps(response)):
            with self.assertRaises(RuntimeError):
                smoke.api("test/")

    def test_new_runs_prune_older_evidence_and_keep_other_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / ".cache/sentry-hang-smoke"
            other = ["DerivedData", "HangProbe.xcodeproj"]
            seeded = [f"{index:032x}" for index in range(5)]
            for index, name in enumerate([*other, *seeded]):
                (output / name).mkdir(parents=True)
                os.utime(output / name, ns=((index + 1) * 10**9,) * 2)
            (output / "notes.txt").write_text("keep")
            other.append("notes.txt")
            run, evidence = smoke.start_run(output)
            self.assertEqual(evidence, output / run)
            self.assertTrue(evidence.is_dir())
            self.assertEqual({path.name for path in output.iterdir()}, {*other, *seeded[-2:], run})
            later, _ = smoke.start_run(output)
            self.assertEqual({path.name for path in output.iterdir()}, {*other, seeded[-1], run, later})


if __name__ == "__main__":
    unittest.main()
