"""Validate the recovered-hang smoke's Sentry API helper."""

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import json
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
