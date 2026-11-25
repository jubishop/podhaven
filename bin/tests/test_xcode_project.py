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

    def test_every_target_inherits_compilation_caching(self):
        # Without the compilation cache, Xcode keeps an explicit module whose inputs look older than it, as a binary
        # package's headers do after its pin changes, so the target compiles against the other pin's module and fails.
        text = PROJECT.read_text()
        project_list = re.search(r"buildConfigurationList = (\w+) /\* Build configuration list for PBXProject ", text)
        self.assertIsNotNone(project_list, "No project build configuration list found")
        configurations = re.search(rf"(?ms)^\s*{project_list[1]} /\*.*?buildConfigurations = \((.*?)\);", text)
        self.assertIsNotNone(configurations, "No project build configurations found")
        identifiers = re.findall(r"\b([0-9A-F]{24})\b", configurations[1])
        self.assertTrue(identifiers, "The project lists no build configurations")
        for identifier in identifiers:
            with self.subTest(configuration=identifier):
                block = re.search(rf"(?ms)^\s*{identifier} /\* (\w+) \*/ = \{{.*?^\s*name = \1;", text)
                self.assertIsNotNone(block, f"No build configuration {identifier} found")
                self.assertTrue("COMPILATION_CACHE_ENABLE_CACHING = YES;" in block[0],
                                f"The project's {block[1]} configuration must enable compilation caching")
        values = set(re.findall(r"(?m)^\s*COMPILATION_CACHE_ENABLE_CACHING\s*=\s*\"?([^\";]+)\"?;", text))
        self.assertEqual(values, {"YES"}, "A target must not override the project's compilation caching")


if __name__ == "__main__":
    unittest.main()
