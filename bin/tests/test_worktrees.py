"""Exercise cache deletion against disposable Git checkouts and real files."""

import getpass
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from contextlib import contextmanager, redirect_stdout
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import hang_guard
import service_guard

SOURCE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SOURCE))
import _worktrees as caches

REVISION = "a" * 40


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

    def seed(self, alias):
        """Fill the shared seed as SwiftPM leaves it: paths recorded through whichever folder resolved them."""
        shutil.rmtree(self.shared)
        self.artifact.parent.mkdir(parents=True)
        self.artifact.write_text("Keep the shared artifact")
        (self.shared / "artifacts/direct").mkdir()
        (self.shared / "artifacts/direct/Direct.xcframework").write_text("Recorded through the seed itself")
        (self.shared / "artifacts/custom").mkdir()
        (self.shared / "artifacts/custom/Custom.xcframework").write_text("Recorded through a deleted custom location")
        (self.shared / "repositories/Factory-1/objects").mkdir(parents=True)
        git = self.shared / "checkouts/Factory/.git"
        (git / "objects/info").mkdir(parents=True)
        (git / "HEAD").write_text(REVISION + "\n")
        (git / "objects/info/alternates").write_text(str(alias / "repositories/Factory-1/objects") + "\n")
        (git / "config").write_text('[remote "origin"]\n\turl = ' + str(alias / "repositories/Factory-1") + "\n")
        source = self.shared / "checkouts/Factory/Sources/Factory.swift"
        source.parent.mkdir(parents=True)
        source.write_text("// pinned")
        # SwiftPM leaves checkout files and their Git config read-only.
        for path in (git / "config", source):
            path.chmod(0o444)
        (self.shared / "workspace-state.json").write_text(json.dumps({"version": 7, "object": {
            "artifacts": [{"path": str(alias / "artifacts/sentry/Sentry.xcframework")},
                          {"path": str(self.shared / "artifacts/direct/Direct.xcframework")},
                          {"path": str(self.base / "repro/dd after/SourcePackages/artifacts/custom/Custom.xcframework")}],
            "dependencies": [
                {"subpath": "Factory", "state": {"name": "sourceControlCheckout", "checkoutState": {"revision": REVISION}}},
                {"subpath": "podhavenmacros", "state": {"name": "fileSystem", "path": str(self.repo / "PodHavenMacros")}},
            ]}}))

    def linked_checkout(self):
        (self.repo / "PodHaven.xcodeproj").mkdir(exist_ok=True)
        (self.repo / "PodHaven.xcodeproj/project.pbxproj").write_text("fixture")
        self.git("add", "PodHaven.xcodeproj/project.pbxproj")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "Project fixture")
        linked = self.repo / "worktrees/linked"
        self.git("-c", "core.hooksPath=/dev/null", "worktree", "add", "-b", "linked", str(linked))
        return linked

    def packages(self, checkout):
        return self.derived / ("PodHaven-" + caches.xcode_hash(checkout / "PodHaven.xcodeproj")) / "SourcePackages"

    def prepare(self, checkout):
        with redirect_stdout(io.StringIO()) as output:
            caches.prepare_xcode(checkout)
        return output.getvalue()

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
            self.assertEqual(future.result(timeout=hang_guard.HANG_LIMIT)["removed"], [str(folder)])

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

    def test_unverified_owner_and_wrong_hash_survive(self):
        outside = self.cache(self.base / "another clone")
        wrong = self.cache(self.repo / "worktrees/wrong")
        wrong = wrong.rename(self.derived / "PodHaven-wronghash")
        result = caches.sweep(self.repo, apply=True)
        self.assertFalse(result["removed"])
        self.assertTrue(all(p.exists() for p in (outside, wrong)))
        self.assertEqual(len(result["deferred"]), 1)

    def test_removes_private_packages_and_never_built_caches_of_removed_checkouts(self):
        built = self.cache()
        (built / "SourcePackages").unlink()
        checkout = built / "SourcePackages/checkouts/Factory/Sources/Factory.swift"
        checkout.parent.mkdir(parents=True)
        checkout.write_text("// pinned")
        checkout.chmod(0o444)
        # Preparation names a checkout's cache before Xcode writes its info.plist on a first build.
        removed = self.repo / "worktrees/never built"
        never_built = self.packages(removed).parent
        (never_built / "SourcePackages").mkdir(parents=True)
        unknown = self.packages(self.base / "unknown checkout").parent
        (unknown / "SourcePackages").mkdir(parents=True)
        state = caches.layout(self.repo)["state"]
        state.mkdir(parents=True)
        (state / "worktrees.json").write_text(json.dumps([str(removed)]))
        result = caches.sweep(self.repo, apply=True)
        self.assertEqual(sorted(result["removed"]), sorted([str(built), str(never_built)]))
        self.assertFalse(built.exists() or never_built.exists())
        self.assertTrue(unknown.is_dir())
        self.assertTrue(self.artifact.is_file())

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

    def test_repairs_seed_paths_recorded_through_a_cache_whose_packages_became_private(self):
        # The seed keeps paths a checkout recorded through its link after preparation gives it a private clone.
        folder = self.cache()
        state = self.metadata(folder)
        (folder / "SourcePackages").unlink()
        shutil.copytree(self.shared, folder / "SourcePackages")
        result = caches.sweep(self.repo, apply=True)
        self.assertEqual(result["removed"], [str(folder)])
        self.assertEqual(json.loads(state.read_text())["object"]["artifacts"][0]["path"], str(self.artifact))
        # A link to anything but the seed still proves nothing about the seed's contents.
        foreign = self.cache(self.repo / "worktrees/foreign")
        (foreign / "SourcePackages").unlink()
        shutil.copytree(self.shared, self.base / "elsewhere")
        (foreign / "SourcePackages").symlink_to(self.base / "elsewhere", target_is_directory=True)
        content = self.metadata(foreign).read_text()
        result = caches.sweep(self.repo, apply=True)
        self.assertFalse(result["removed"])
        self.assertEqual(state.read_text(), content)
        self.assertTrue(foreign.exists())

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
    def test_prepare_gives_each_checkout_private_packages_cloned_from_the_shared_seed(self):
        suffix = Path("PodHaven.xcodeproj/project.xcworkspace/xcuserdata") / (getpass.getuser() + ".xcuserdatad/WorkspaceSettings.xcsettings")
        source = self.repo / suffix
        source.parent.mkdir(parents=True)
        source.write_bytes(plistlib.dumps({"EnableBuildDebugging": True}))
        linked = self.linked_checkout()
        self.seed(self.derived / "PodHaven-removedcheckout/SourcePackages")
        self.prepare(linked)
        folders = [self.packages(p) for p in (self.repo, linked)]
        self.assertNotEqual(*folders)
        for folder in folders:
            self.assertFalse(folder.is_symlink())
            state = json.loads((folder / "workspace-state.json").read_text())["object"]
            self.assertEqual([artifact["path"] for artifact in state["artifacts"]],
                             [str(folder / "artifacts/sentry/Sentry.xcframework"),
                              str(folder / "artifacts/direct/Direct.xcframework"),
                              str(folder / "artifacts/custom/Custom.xcframework")])
            self.assertEqual(Path(state["artifacts"][0]["path"]).read_text(), "Keep the shared artifact")
            self.assertEqual(state["dependencies"][1]["state"]["path"], str(self.repo / "PodHavenMacros"))
            git = folder / "checkouts/Factory/.git"
            self.assertEqual((git / "objects/info/alternates").read_text(),
                             str(folder / "repositories/Factory-1/objects") + "\n")
            self.assertIn("url = " + str(folder / "repositories/Factory-1") + "\n", (git / "config").read_text())
        self.assertEqual(caches.package_folder(linked), folders[1])
        # A package switch in one checkout reaches neither the other checkout nor the seed.
        switched = folders[1] / "checkouts/Factory/Sources/Factory.swift"
        switched.chmod(0o644)
        switched.write_text("// switched")
        for folder in (folders[0], self.shared):
            self.assertEqual((folder / "checkouts/Factory/Sources/Factory.swift").read_text(), "// pinned")
        self.assertEqual((linked / suffix).read_bytes(), source.read_bytes())
        before = source.read_bytes()
        self.prepare(linked)
        self.assertEqual(source.read_bytes(), before)
        self.assertEqual(switched.read_text(), "// switched")

    @unittest.skipUnless(sys.platform == "darwin", "Xcode preparation is macOS-only")
    def test_prepare_keeps_a_shared_link_until_its_checkout_is_idle_and_its_clone_is_ready(self):
        linked = self.linked_checkout()
        folder = self.packages(linked)
        # Checkouts that still link the seed read the paths it recorded through this link.
        self.seed(folder)
        folder.parent.mkdir(parents=True)
        folder.symlink_to(self.shared, target_is_directory=True)
        self.open.side_effect = lambda path: path == folder.parent
        self.assertIn("in use", self.prepare(linked))
        self.assertEqual(folder.resolve(), self.shared)
        self.open.side_effect = None
        lock = self.shared / "checkouts/Factory/.git/index.lock"
        lock.touch()
        self.assertIn("stay shared until", self.prepare(linked))
        self.assertEqual(folder.resolve(), self.shared)
        lock.unlink()
        self.prepare(linked)
        self.assertFalse(folder.is_symlink())
        self.assertEqual(json.loads((folder / "workspace-state.json").read_text())["object"]["artifacts"][0]["path"],
                         str(folder / "artifacts/sentry/Sentry.xcframework"))

    @unittest.skipUnless(sys.platform == "darwin", "Xcode preparation is macOS-only")
    def test_a_seed_caught_mid_update_leaves_packages_for_xcode_to_resolve(self):
        linked = self.linked_checkout()
        git = self.shared / "checkouts/Factory/.git"
        damages = {"switched checkout": lambda: (git / "HEAD").write_text("b" * 40 + "\n"),
                   "checkout in progress": lambda: (git / "index.lock").touch(),
                   "missing artifact": lambda: self.artifact.unlink(),
                   "missing objects": lambda: (self.shared / "repositories/Factory-1/objects").rmdir(),
                   "partial metadata": lambda: (self.shared / "workspace-state.json").write_text("{")}
        for name, damage in damages.items():
            with self.subTest(name):
                self.seed(self.shared)
                damage()
                self.assertIn("Xcode will resolve packages afresh", self.prepare(linked))
                folder = self.packages(linked)
                self.assertFalse(folder.exists() or folder.is_symlink())
                self.assertEqual(list(folder.parent.iterdir()), [])

    @unittest.skipUnless(sys.platform == "darwin", "Xcode preparation is macOS-only")
    def test_a_link_to_a_missing_seed_leaves_packages_for_xcode_to_resolve(self):
        linked = self.linked_checkout()
        shutil.rmtree(self.shared)
        folder = self.packages(linked)
        folder.parent.mkdir(parents=True)
        folder.symlink_to(self.shared, target_is_directory=True)
        self.prepare(linked)
        self.assertFalse(folder.exists() or folder.is_symlink())

    def test_cleanup_agent_runs_the_default_python_that_follows_updates(self):
        home, tools = self.base / "home", self.base / "tools"
        tools.mkdir()
        calls = self.base / "launchctl.jsonl"
        launchctl = tools / "launchctl"
        launchctl.write_text(f"#!{sys.executable}\nimport json,sys\n"
                             f"with open({str(calls)!r}, 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
                             "sys.exit(1 if sys.argv[1] == 'print' else 0)\n")
        launchctl.chmod(0o755)
        python = home / ".local/bin/python3"
        with patch.object(caches.sys, "platform", "darwin"), patch.object(Path, "home", return_value=home), \
                patch.dict(os.environ, {"PATH": str(tools) + os.pathsep + os.environ["PATH"]}), \
                redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "uv python install --default"):
                caches.install_agent(self.repo)
            self.assertFalse(calls.exists())
            python.parent.mkdir(parents=True)
            python.symlink_to(sys.executable)
            caches.install_agent(self.repo)
        plist = home / "Library/LaunchAgents" / (caches.LABEL + ".plist")
        self.assertEqual(plistlib.loads(plist.read_bytes())["ProgramArguments"],
                         ["/bin/sh", "-c", 'exec "$0" "$@"', str(python),
                          str(self.repo / "bin/prune-worktree-caches"), "--apply", "--quiet"])
        self.assertEqual([json.loads(line)[0] for line in calls.read_text().splitlines()], ["print", "bootstrap"])

    @contextmanager
    def running_agent(self, lingers):
        # Like launchd stopping a running job: the old service lingers after bootout, and bootstrap fails until it is gone.
        home, tools = self.base / "home", self.base / "tools"
        tools.mkdir()
        python = home / ".local/bin/python3"
        python.parent.mkdir(parents=True)
        python.symlink_to(sys.executable)
        calls = self.base / "launchctl.jsonl"
        launchctl = tools / "launchctl"
        launchctl.write_text(f"#!{sys.executable}\nimport json, pathlib, sys\n"
                             f"calls = pathlib.Path({str(calls)!r})\n"
                             "names = [json.loads(line)[0] for line in calls.read_text().splitlines()] if calls.exists() else []\n"
                             "with calls.open('a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                             f"present = 'bootout' not in names or names[names.index('bootout') + 1:].count('print') < {lingers}\n"
                             "sys.exit({'print': 0 if present else 113, 'bootstrap': 5 if present else 0}.get(sys.argv[1], 0))\n")
        launchctl.chmod(0o755)
        clock = [0.0]
        def sleep(seconds):
            clock[0] += seconds
        with patch.object(caches.sys, "platform", "darwin"), patch.object(Path, "home", return_value=home), \
                patch.dict(os.environ, {"PATH": str(tools) + os.pathsep + os.environ["PATH"]}), \
                patch("time.monotonic", lambda: clock[0]), patch("time.sleep", sleep), redirect_stdout(io.StringIO()):
            yield lambda: [json.loads(line)[0] for line in calls.read_text().splitlines()]

    def test_reinstall_bootstraps_once_the_running_agent_is_gone(self):
        with self.running_agent(lingers=3) as launchctl_calls:
            caches.install_agent(self.repo)
            self.assertEqual(launchctl_calls(), ["print", "bootout", "print", "print", "print", "print", "bootstrap"])

    def test_reinstall_fails_clearly_when_the_agent_never_stops(self):
        with self.running_agent(lingers=10**6) as launchctl_calls:
            with self.assertRaisesRegex(RuntimeError, "launchd did not stop " + caches.LABEL + " within 30 seconds"):
                caches.install_agent(self.repo)
            self.assertNotIn("bootstrap", launchctl_calls())

    def unloaded_agent(self):
        tools = self.base / "tools"
        tools.mkdir(exist_ok=True)
        launchctl = tools / "launchctl"
        launchctl.write_text("#!/bin/sh\nexit 1\n")
        launchctl.chmod(0o755)
        return {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"]}

    @unittest.skipUnless(sys.platform == "darwin", "Xcode diagnostics are macOS-only")
    def test_health_reports_shared_packages_and_cleanup_failures_as_issues_and_the_rest_as_notices(self):
        (self.repo / "PodHaven.xcodeproj").mkdir()
        link = self.packages(self.repo)
        link.parent.mkdir()
        link.symlink_to(self.shared, target_is_directory=True)
        error = self.repo / ".cache/worktree-cleanup/last-error.json"
        error.parent.mkdir(parents=True)
        error.write_text(json.dumps({"at": "2026-10-26T09:00:00-07:00", "error": "Disk full"}))
        state = Path(self.git("rev-parse", "--path-format=absolute", "--git-common-dir").strip()) / "knowledge/xcode"
        state.mkdir(parents=True)
        (state / "cleanup.json").write_text(json.dumps({"deferred": [{"path": "/caches/old", "reason": "Xcode is open"}]}))
        with patch.dict(os.environ, self.unloaded_agent()):
            report = caches.xcode_health(self.repo)
        self.assertEqual(report["issues"], ["Xcode packages are shared with other checkouts; run bin/prep-worktree.",
                                            "Automatic cleanup failed; inspect cleanup_error in bin/doctor-xcode --json."])
        self.assertEqual(report["notices"], ["Hourly cleanup is not loaded; run bin/install-cleanup-agent in the primary checkout.",
                                             "Cleanup deferred: /caches/old: Xcode is open"])

    @unittest.skipUnless(sys.platform == "darwin", "Xcode preparation is macOS-only")
    def test_application_setup_prepares_xcode_and_the_doctor_reports_it_healthy(self):
        (self.repo / "bin").mkdir()
        for name in ("setup-application", "doctor-xcode", "_worktrees.py", "_knowledge.py"):
            shutil.copy2(SOURCE / name, self.repo / "bin" / name)
        (self.repo / "PodHaven.xcodeproj").mkdir()
        environment = self.unloaded_agent()
        subprocess.run([str(self.repo / "bin/setup-application")], cwd=self.repo, env=environment, check=True,
                       capture_output=True)
        folder = self.packages(self.repo)
        self.assertFalse(folder.is_symlink())
        self.assertEqual((folder / "artifacts/sentry/Sentry.xcframework").read_text(), "Keep the shared artifact")
        result = subprocess.run([str(self.repo / "bin/doctor-xcode"), "--json"], cwd=self.repo, env=environment,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["packages_private"])
        self.assertEqual(report["issues"], [])


if __name__ == "__main__":
    unittest.main()
