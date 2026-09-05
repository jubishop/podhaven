"""Exercise cache deletion against disposable Git checkouts and real files."""

import getpass
from concurrent.futures import ThreadPoolExecutor, TimeoutError
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import _worktrees as caches


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="podhaven caches ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Cache test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "Fixture")
        self.derived = self.base / "DerivedData"
        self.shared = self.base / "Shared packages"
        self.derived.mkdir()
        (self.shared / "artifacts/sentry").mkdir(parents=True)
        self.artifact = self.shared / "artifacts/sentry/Sentry.xcframework"
        self.artifact.write_text("Keep the shared artifact")
        self.git("config", "knowledge.xcodeDerivedDataPath", str(self.derived))
        self.git("config", "knowledge.xcodePackagesPath", str(self.shared))
        self.busy = patch.object(caches, "build_activity", return_value=False).start()
        self.open = patch.object(caches, "path_in_use", return_value=False).start()
        self.addCleanup(patch.stopall)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.DEVNULL, text=True)

    def cache(self, owner=None):
        owner = owner or self.repo / "worktrees/removed"
        project = owner / "PodHaven.xcodeproj"
        folder = self.derived / ("PodHaven-" + caches.xcode_hash(project))
        folder.mkdir()
        (folder / "info.plist").write_bytes(plistlib.dumps({"WorkspacePath": str(project / "project.xcworkspace")}))
        (folder / "SourcePackages").symlink_to(self.shared, target_is_directory=True)
        (folder / "Build").mkdir()
        (folder / "Build/object.o").write_bytes(b"x" * 8192)
        return folder

    def metadata(self, folder):
        path = self.shared / "workspace-state.json"
        path.write_text(json.dumps({"object": {"artifacts": [{"path": str(folder / "SourcePackages/artifacts/sentry/Sentry.xcframework")} ]}}))
        return path

    def test_repairs_shared_artifact_before_removing_orphan(self):
        folder = self.cache()
        state = self.metadata(folder)
        result = caches.sweep(self.repo, apply=True)
        self.assertEqual(result["removed"], [str(folder)])
        self.assertFalse(folder.exists())
        target = json.loads(state.read_text())["object"]["artifacts"][0]["path"]
        self.assertEqual(target, str(self.artifact))
        self.assertEqual(Path(target).read_text(), "Keep the shared artifact")
        self.assertGreater(result["removed_cache_bytes"], 0)
        self.assertEqual(caches.sweep(self.repo, apply=True)["removed"], [])

    def test_cleanup_waits_for_the_shared_preparation_lock(self):
        folder = self.cache()
        with ThreadPoolExecutor(max_workers=1) as executor:
            with caches.maintenance_lock(caches.layout(self.repo)):
                future = executor.submit(caches.sweep, self.repo, True)
                with self.assertRaises(TimeoutError):
                    future.result(timeout=0.1)
                self.assertTrue(folder.exists())
            self.assertEqual(future.result(timeout=10)["removed"], [str(folder)])

    def test_partial_deletion_preserves_ownership_for_automatic_retry(self):
        folder = self.cache()
        self.metadata(folder)
        with patch.object(caches.shutil, "rmtree", side_effect=PermissionError("Busy build directory")):
            report = caches.sweep(self.repo, apply=True)
        self.assertFalse(report["removed"])
        self.assertTrue(report["deferred"])
        self.assertTrue((folder / "info.plist").is_file())
        self.assertEqual(caches.sweep(self.repo, apply=True)["removed"], [str(folder)])
        self.assertTrue(self.artifact.is_file())

    def test_dry_run_preserves_cache_and_metadata(self):
        folder = self.cache()
        state = self.metadata(folder)
        before = state.read_bytes()
        result = caches.sweep(self.repo)
        self.assertEqual(result["candidates"], [str(folder)])
        self.assertEqual(result["removed"], [])
        self.assertEqual(state.read_bytes(), before)
        self.assertTrue(folder.is_dir())
        self.assertFalse(caches.layout(self.repo)["state"].exists())

    def test_live_registered_missing_and_existing_unregistered_owners_survive(self):
        live = self.repo / "worktrees/live"
        self.git("-c", "core.hooksPath=/dev/null", "worktree", "add", "-b", "live", str(live))
        folder = self.cache(live)
        other = self.repo / "worktrees/unregistered"
        other.mkdir()
        other_cache = self.cache(other)
        self.assertEqual(caches.sweep(self.repo, apply=True)["removed"], [])
        live.rename(self.base / "temporarily moved")
        self.assertEqual(caches.sweep(self.repo, apply=True)["removed"], [])
        self.assertTrue(folder.exists() and other_cache.exists())

    def test_unverified_owner_wrong_hash_and_independent_packages_survive(self):
        outside = self.cache(self.base / "another clone")
        wrong = self.cache(self.repo / "worktrees/wrong")
        wrong = wrong.rename(self.derived / "PodHaven-wronghash")
        independent = self.cache()
        (independent / "SourcePackages").unlink()
        (independent / "SourcePackages").mkdir()
        result = caches.sweep(self.repo, apply=True)
        self.assertFalse(result["removed"])
        self.assertTrue(all(p.exists() for p in (outside, wrong, independent)))
        self.assertEqual(len(result["deferred"]), 2)

    def test_busy_builds_and_open_files_defer_without_metadata_writes(self):
        folder = self.cache()
        state = self.metadata(folder)
        before = state.read_bytes()
        self.busy.return_value = True
        self.assertFalse(caches.sweep(self.repo, apply=True)["removed"])
        self.busy.return_value = False
        self.open.return_value = True
        self.assertFalse(caches.sweep(self.repo, apply=True)["removed"])
        self.assertEqual(state.read_bytes(), before)
        self.assertTrue(folder.exists())

    def test_idle_xcode_still_blocks_shared_metadata_repair(self):
        folder = self.cache()
        self.metadata(folder)
        self.busy.side_effect = lambda include_ide=False: include_ide
        result = caches.sweep(self.repo, apply=True)
        self.assertFalse(result["removed"])
        self.assertIn("waiting for Xcode", result["deferred"][0]["reason"])

    def test_malformed_metadata_missing_artifact_and_escaping_path_defer(self):
        folder = self.cache()
        state = self.metadata(folder)
        for content in ("broken JSON", json.dumps({"path": str(folder / "SourcePackages/missing")}),
                        json.dumps({"path": str(folder / "SourcePackages/../outside")})):
            with self.subTest(content=content):
                state.write_text(content)
                result = caches.sweep(self.repo, apply=True)
                self.assertFalse(result["removed"])
                self.assertTrue(result["deferred"])
                self.assertEqual(state.read_text(), content)
                self.assertTrue(folder.exists())

    @unittest.skipUnless(sys.platform == "darwin", "Xcode preparation is macOS-only")
    def test_prepare_shares_packages_copies_settings_and_keeps_derived_data_private(self):
        suffix = Path("PodHaven.xcodeproj/project.xcworkspace/xcuserdata") / (getpass.getuser() + ".xcuserdatad/WorkspaceSettings.xcsettings")
        source = self.repo / suffix
        source.parent.mkdir(parents=True)
        source.write_bytes(plistlib.dumps({"EnableBuildDebugging": True}))
        (self.repo / "PodHaven.xcodeproj/project.pbxproj").write_text("fixture")
        self.git("add", "PodHaven.xcodeproj/project.pbxproj")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "Project fixture")
        linked = self.repo / "worktrees/linked"
        self.git("-c", "core.hooksPath=/dev/null", "worktree", "add", "-b", "linked", str(linked))
        caches.prepare_xcode(linked)
        paths = [self.derived / ("PodHaven-" + caches.xcode_hash(p / "PodHaven.xcodeproj")) for p in (self.repo, linked)]
        self.assertNotEqual(*paths)
        self.assertTrue(all((p / "SourcePackages").resolve() == self.shared for p in paths))
        self.assertEqual((linked / suffix).read_bytes(), source.read_bytes())
        before = source.read_bytes()
        caches.prepare_xcode(linked)
        self.assertEqual(source.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
