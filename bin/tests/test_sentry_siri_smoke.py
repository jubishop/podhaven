"""Preserve Siri smoke validation failures when the probe already exited."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader("siri_smoke", str(ROOT / "bin/sentry-siri-smoke"))
spec = importlib.util.spec_from_loader(loader.name, loader)
smoke = importlib.util.module_from_spec(spec)
loader.exec_module(smoke)


class SiriSmokeTests(unittest.TestCase):
    def test_exited_probe_does_not_replace_event_timeout(self):
        calls = []

        def run(args, **kwargs):
            calls.append(tuple(args))
            if args[:3] == ["xcrun", "simctl", "terminate"]:
                if kwargs.get("check"):
                    raise subprocess.CalledProcessError(3, args)
                return subprocess.CompletedProcess(args, 3)
            return subprocess.CompletedProcess(args, 0)

        def command(*args, **kwargs):
            calls.append(args)
            if args[:4] == ("xcrun", "simctl", "list", "devices"):
                return json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    {"udid": "test-simulator", "state": "Booted"}]}})
            if args[:3] == ("xcrun", "xcresulttool", "get"):
                return json.dumps({"errorCount": 0, "analyzerWarningCount": 0, "warningCount": 0})
            if args[:3] == ("xcrun", "simctl", "terminate"):
                raise subprocess.CalledProcessError(3, args)
            return ""

        with tempfile.TemporaryDirectory() as directory, \
                patch.object(smoke, "ROOT", Path(directory)), \
                patch.object(smoke, "command", command), \
                patch.object(smoke, "load"), \
                patch.object(smoke.probe, "source_state", return_value={"gitCommitHash": "test"}), \
                patch.object(smoke.probe, "prepare", return_value=Path(directory) / "Probe.xcodeproj"), \
                patch.object(smoke.subprocess, "run", side_effect=run), \
                patch.object(smoke.time, "monotonic", side_effect=[0, 181]), \
                patch.dict(smoke.os.environ, {"SENTRY_AUTH_TOKEN": "test-token"}), \
                patch("sys.argv", ["sentry-siri-smoke", "--device", "test-simulator"]):
            with self.assertRaisesRegex(RuntimeError, "Both controlled events did not arrive"):
                smoke.main()
        self.assertIn(("xcrun", "simctl", "terminate", "test-simulator", smoke.BUNDLE), calls)


if __name__ == "__main__":
    unittest.main()
