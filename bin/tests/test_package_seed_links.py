"""Exercise bin/test-all and bin/with-my-mac-lock with a checkout whose DerivedData still links the package seed."""

import shutil
import sys
import unittest

import hang_guard
import service_guard
from test_test_all import ROOT, TestAllFixture

sys.path.insert(0, str(ROOT / "bin"))
from _worktrees import SHARED_PACKAGES, xcode_hash

TOOLCHAIN = [["xcodebuild", ["-hideShellScriptEnvironment", "-version"]], ["xcrun", ["swift", "--version"]],
             ["sw_vers", ["-productVersion"]]]


@unittest.skipUnless(sys.platform == "darwin", "Package clones are macOS-only")
class PackageSeedLinkTests(TestAllFixture):
    def setUp(self):
        super().setUp()
        shutil.copy2(ROOT / "bin/with-my-mac-lock", self.repo / "bin/with-my-mac-lock")
        developer = self.base / "home/Library/Developer"
        self.seed = developer / "SharedSourcePackages/PodHaven"
        (self.seed / "artifacts/sentry").mkdir(parents=True)
        (self.seed / "artifacts/sentry/Sentry.xcframework").write_text("Seed artifact")
        project = self.repo.resolve() / "PodHaven.xcodeproj"
        self.packages = developer / "Xcode/DerivedData" / ("PodHaven-" + xcode_hash(project)) / "SourcePackages"
        self.packages.parent.mkdir(parents=True)
        self.packages.symlink_to(self.seed, target_is_directory=True)

    def lock_command(self, *command, **env):
        return hang_guard.run([sys.executable, "-B", str(self.repo / "bin/with-my-mac-lock"), *command],
                              cwd=self.repo, env={**self.env, **env}, text=True, capture_output=True)

    def assert_private(self):
        self.assertFalse(self.packages.is_symlink())
        self.assertEqual((self.packages / "artifacts/sentry/Sentry.xcframework").read_text(), "Seed artifact")
        self.assertTrue(self.seed.is_dir() and not self.seed.is_symlink())

    def assert_still_linked(self):
        self.assertEqual(self.packages.resolve(), self.seed.resolve())

    def test_a_full_run_moves_the_checkout_onto_a_clone_of_the_seed_and_passes(self):
        result = self.run_all()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_private()

    def test_a_link_that_must_stay_fails_the_run_before_any_xcode_build_or_phase(self):
        result = self.run_all(TEST_FOLDER_IN_USE="1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Packages stay shared while this checkout's DerivedData is in use", result.stdout)
        self.assertEqual(result.stderr, f"error: {SHARED_PACKAGES}\n")
        self.assertEqual([event for event in self.events() if event[0] != "lsof"], TOOLCHAIN)
        self.assert_still_linked()

    def test_a_focused_command_runs_once_the_checkout_has_a_clone_of_the_seed(self):
        result = self.lock_command("/bin/echo", "ran")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ran\n")
        self.assert_private()

    def test_a_link_that_must_stay_stops_a_focused_command_before_it_runs(self):
        result = self.lock_command("/bin/echo", "ran", TEST_FOLDER_IN_USE="1")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertNotIn("ran\n", result.stdout)
        self.assertEqual(result.stderr, f"with-my-mac-lock: {SHARED_PACKAGES}\n")
        # It took neither a validation slot nor the My Mac test lock.
        self.assertFalse((self.base / "home/.cache/podhaven").exists())
        self.assert_still_linked()


if __name__ == "__main__":
    unittest.main()
