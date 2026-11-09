"""Check settings that every PodHaven Xcode build configuration must share."""

from pathlib import Path
import re
import unittest

import service_guard


PROJECT = Path(__file__).resolve().parents[2] / "PodHaven.xcodeproj/project.pbxproj"


class XcodeProjectTests(unittest.TestCase):
    def test_every_configuration_shares_one_ios_deployment_target(self):
        # The system won't load an extension whose deployment target is newer than the OS.
        targets = re.findall(r"(?m)^\s*IPHONEOS_DEPLOYMENT_TARGET\s*=\s*\"?([^\";]+)\"?;", PROJECT.read_text())
        self.assertTrue(targets, "No IPHONEOS_DEPLOYMENT_TARGET found")
        self.assertEqual(len(set(targets)), 1, f"Mixed iOS deployment targets: {sorted(set(targets))}")


if __name__ == "__main__":
    unittest.main()
