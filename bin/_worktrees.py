"""Prepare Xcode caches and reclaim verified orphan caches on macOS."""

import ctypes
import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import time
from contextlib import contextmanager

from _knowledge import atomic_json, git, git_environment, primary_checkout, read_json, stamp

LABEL = "com.jubi.podhaven.worktree-cleanup"


def xcode_hash(path):
    numbers = struct.unpack(">QQ", hashlib.md5(str(path).encode()).digest())
    result = ""
    for number in numbers:
        letters = ""
        for _ in range(14):
            letters = chr(97 + number % 26) + letters
            number //= 26
        result += letters
    return result


def layout(root):
    root = root.resolve()
    if Path(git("rev-parse", "--show-toplevel", root=root)).resolve() != root:
        raise ValueError("Expected a Git checkout root")
    primary = primary_checkout(root)
    if not primary:
        raise ValueError("Xcode preparation requires a primary checkout")
    def location(key, default):
        value = git("config", "--local", "--get", "knowledge." + key, root=root, optional=True)
        path = Path(value).expanduser() if value else default
        if not path.is_absolute():
            raise ValueError(key + " must be absolute")
        path = path.resolve()
        if path in (Path('/'), Path.home(), root, primary):
            raise ValueError("Unsafe cache root: " + str(path))
        return path
    derived = location("xcodeDerivedDataPath", Path.home() / "Library/Developer/Xcode/DerivedData")
    packages = location("xcodePackagesPath", Path.home() / "Library/Developer/SharedSourcePackages/PodHaven")
    if packages.is_relative_to(derived) or derived.is_relative_to(packages):
        raise ValueError("Shared packages must be outside DerivedData")
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", root=root))
    return {"root": root, "primary": primary, "derived": derived, "packages": packages,
            "state": common / "knowledge/xcode", "lock": packages.parent / (packages.name + ".maintenance.lock")}


def checkout_cache(paths, checkout):
    return paths["derived"] / ("PodHaven-" + xcode_hash(checkout / "PodHaven.xcodeproj"))


def package_folder(root):
    """Return the checkout's own SwiftPM folder, where its Xcode builds resolve packages."""
    paths = layout(root)
    return checkout_cache(paths, paths["root"]) / "SourcePackages"


@contextmanager
def maintenance_lock(paths):
    path = paths["lock"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def registered_worktrees(root):
    raw = subprocess.check_output(["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"], env=git_environment())
    return {str(Path(os.fsdecode(field[9:])).resolve()) for field in raw.split(b"\0") if field.startswith(b"worktree ")}


def build_activity(include_ide=False):
    result = subprocess.run(["ps", "-axo", "comm="], text=True, capture_output=True, timeout=15)
    if result.returncode:
        return True
    names = {"xcodebuild", "swift-build", "swift-package", "swift-frontend", "clang", "clang++", "ld"}
    if include_ide:
        names.add("Xcode")
    return any(Path(line.strip()).name in names for line in result.stdout.splitlines())


def path_in_use(path):
    command = shutil.which("lsof") or "/usr/sbin/lsof"
    try:
        result = subprocess.run([command, "+D", str(path)], text=True, capture_output=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return True
    return result.returncode != 1 or bool(result.stdout.strip()) or bool(result.stderr.strip())


def cache_owner(folder, named):
    if folder.is_symlink() or not folder.is_dir():
        return None
    try:
        workspace = Path(plistlib.loads((folder / "info.plist").read_bytes())["WorkspacePath"])
    except FileNotFoundError:
        # Xcode writes info.plist on a checkout's first build; preparation names the folder for a known checkout.
        return named.get(folder.name)
    except (OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException):
        return None
    project = workspace.parent if workspace.name == "project.xcworkspace" else workspace
    if not project.is_absolute() or project.name != "PodHaven.xcodeproj":
        return None
    if folder.name != "PodHaven-" + xcode_hash(project):
        return None
    return project.parent.resolve()


def artifact_references(value, folder, packages):
    """Return verified canonical replacements; refuse unrelated cache references."""
    changed = False
    if isinstance(value, dict):
        result = {}
        for key, child in value.items():
            result[key], edited = artifact_references(child, folder, packages)
            changed |= edited
        return result, changed
    if isinstance(value, list):
        result = []
        for child in value:
            item, edited = artifact_references(child, folder, packages)
            result.append(item)
            changed |= edited
        return result, changed
    if isinstance(value, str) and value.startswith(str(folder) + os.sep):
        source = Path(value)
        alias = folder / "SourcePackages"
        # A folder made private after recording these paths no longer shares files with the seed to compare.
        linked = alias.is_symlink()
        if not source.is_relative_to(alias) or (linked and alias.resolve() != packages):
            raise ValueError("Shared metadata references an unshared cache path")
        relative = source.relative_to(alias)
        if ".." in relative.parts:
            raise ValueError("Shared metadata contains a path traversal")
        target = (packages / relative).resolve()
        if (not target.is_relative_to(packages) or not target.exists()
                or (linked and not (source.exists() and os.path.samefile(source, target)))):
            raise ValueError("Cannot verify the shared artifact replacement")
        return str(target), True
    return value, False


def allocated_bytes(folder):
    total = 0
    for directory, _, files in os.walk(folder, followlinks=False):
        for name in files:
            try:
                total += (Path(directory) / name).lstat().st_blocks * 512
            except FileNotFoundError:
                pass
    return total


def sweep(root, apply=False):
    paths = layout(root)
    report = {"at": stamp(), "apply": apply, "removed": [], "candidates": [], "deferred": [], "removed_cache_bytes": 0}
    if not paths["derived"].is_dir():
        return report
    with maintenance_lock(paths):
        live = registered_worktrees(root)
        registry = read_json(paths["state"] / "worktrees.json", [])
        known = set(registry) | live
        if apply:
            atomic_json(paths["state"] / "worktrees.json", sorted(known))
        named = {checkout_cache(paths, Path(checkout)).name: Path(checkout) for checkout in known}
        for folder in sorted(paths["derived"].glob("PodHaven-*")):
            owner = cache_owner(folder, named)
            if owner is None or str(owner) in live or owner.exists():
                continue
            if str(owner) not in known and not owner.is_relative_to(paths["primary"] / "worktrees"):
                report["deferred"].append({"path": str(folder), "reason": "Ownership by this clone is unverified"})
                continue
            report["candidates"].append(str(folder))
            try:
                if build_activity() or path_in_use(folder):
                    raise ValueError("Build or open-file activity; automatic cleanup will retry")
                # Checkouts that still link the seed may record paths through this cache's link; move those first.
                state = paths["packages"] / "workspace-state.json"
                before = state.read_bytes() if state.exists() else None
                parsed = json.loads(before) if before is not None else {}
                updated, changed = artifact_references(parsed, folder, paths["packages"])
                if changed and (build_activity(include_ide=True) or path_in_use(paths["packages"])):
                    raise ValueError("Shared metadata needs repair; waiting for Xcode and package users to close")
                if not apply:
                    continue
                # Repeat ownership, activity, and metadata checks immediately before mutation.
                if owner.exists() or str(owner) in registered_worktrees(root) or cache_owner(folder, named) != owner:
                    raise ValueError("Checkout or cache ownership changed during inspection")
                if build_activity(include_ide=changed) or path_in_use(folder):
                    raise ValueError("Build or cache activity started; automatic cleanup will retry")
                if (state.read_bytes() if state.exists() else None) != before:
                    raise ValueError("SwiftPM metadata changed during inspection")
                if changed:
                    atomic_json(state, updated)
                    if json.loads(state.read_bytes()) != updated:
                        raise ValueError("Shared metadata repair readback failed")
                size = allocated_bytes(folder)
                # Retain ownership evidence if a partial deletion fails, so a
                # later automatic attempt can safely finish the same cache.
                for child in folder.iterdir():
                    if child.name == "info.plist":
                        continue
                    if child.is_dir() and not child.is_symlink():
                        shutil.rmtree(child)
                    else:
                        child.unlink()
                (folder / "info.plist").unlink(missing_ok=True)
                folder.rmdir()
                report["removed"].append(str(folder))
                report["removed_cache_bytes"] += size
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                report["deferred"].append({"path": str(folder), "reason": str(error)})
        if apply:
            atomic_json(paths["state"] / "cleanup.json", report)
    return report


def clonefile(source, target):
    """Make target an APFS copy-on-write clone of the whole source tree."""
    clone = ctypes.CDLL(None, use_errno=True).clonefile
    clone.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32)
    if clone(os.fsencode(source), os.fsencode(target), 0):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(target))


def relocated(value, roots, target):
    if isinstance(value, dict):
        return {key: relocated(child, roots, target) for key, child in value.items()}
    if isinstance(value, list):
        return [relocated(child, roots, target) for child in value]
    if isinstance(value, str):
        return roots.sub(lambda _: str(target), value)
    return value


def clone_packages(paths, target):
    """Clone the seed to target with the paths SwiftPM recorded moved into the clone, or raise why it can't be."""
    staging = target.with_name(target.name + ".preparing")
    if staging.exists():
        shutil.rmtree(staging)
    clonefile(paths["packages"], staging)
    try:
        # SwiftPM records absolute paths through whichever folder resolved them: the seed itself or a
        # SourcePackages link in any DerivedData, deleted or not.
        roots = re.compile("(?:" + re.escape(str(paths["packages"])) + r"|(?:/[^/\n]+)+?/SourcePackages)(?=/|$)", re.M)

        def staged(value):
            path = Path(value)
            if not path.is_relative_to(target) or ".." in path.relative_to(target).parts:
                raise ValueError("The seed records a path outside its packages: " + value)
            return staging / path.relative_to(target)

        # Each checkout borrows Git objects from, and names as its origin, a clone under repositories.
        for repository in staging.glob("checkouts/*/.git"):
            alternates = repository / "objects/info/alternates"
            for path in (alternates, repository / "config"):
                if path.is_file():
                    temporary = path.with_name(path.name + ".relocated")
                    temporary.write_text(roots.sub(lambda _: str(target), path.read_text()))
                    temporary.chmod(path.stat().st_mode)
                    temporary.replace(path)
            for line in filter(None, alternates.read_text().splitlines()) if alternates.is_file() else ():
                if not staged(line).is_dir():
                    raise ValueError("Missing package objects " + line)
        state_path = staging / "workspace-state.json"
        if state_path.exists():
            try:
                state = relocated(json.loads(state_path.read_bytes()), roots, target)
                artifacts = [artifact["path"] for artifact in state["object"].get("artifacts", [])]
                checkouts = [(dependency["subpath"], dependency["state"]["checkoutState"]["revision"])
                             for dependency in state["object"].get("dependencies", [])
                             if dependency["state"]["name"] == "sourceControlCheckout"]
            except (KeyError, TypeError, AttributeError) as error:
                raise ValueError("Unrecognized package metadata in the seed") from error
            for artifact in artifacts:
                if not staged(artifact).exists():
                    raise ValueError("Missing package artifact " + artifact)
            for subpath, revision in checkouts:
                repository = staging / "checkouts" / subpath / ".git"
                if (repository / "index.lock").exists() or (repository / "HEAD").read_text().strip() != revision:
                    raise ValueError("The seed's " + subpath + " checkout was mid-update")
            atomic_json(state_path, state)
        staging.rename(target)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def make_packages_private(paths, directory):
    """Give one checkout's DerivedData its own packages, cloned from the seed; Xcode resolves afresh without them."""
    directory.mkdir(parents=True, exist_ok=True)
    packages = directory / "SourcePackages"
    if packages.is_symlink():
        if packages.resolve() != paths["packages"]:
            print("Preserved existing SourcePackages link; inspect with bin/doctor-xcode: " + str(packages))
            return
        if path_in_use(directory):
            print("Packages stay shared while this checkout's DerivedData is in use; bin/prep-worktree retries: "
                  + str(directory))
            return
        packages.unlink()
    elif packages.exists() or not paths["packages"].is_dir():
        return
    try:
        clone_packages(paths, packages)
    except (OSError, ValueError) as error:
        print("Xcode will resolve packages afresh in " + str(packages) + ": " + str(error))


def prepare_xcode(root):
    if sys.platform != "darwin" or not (root / "PodHaven.xcodeproj").is_dir():
        return
    paths = layout(root)
    with maintenance_lock(paths):
        known = set(read_json(paths["state"] / "worktrees.json", [])) | registered_worktrees(root)
        atomic_json(paths["state"] / "worktrees.json", sorted(known))
        directories = [checkout_cache(paths, checkout) for checkout in dict.fromkeys((paths["primary"], paths["root"]))]
        seed = paths["packages"]
        if not seed.exists():
            source = next((d / "SourcePackages" for d in directories
                           if (d / "SourcePackages").is_dir() and not (d / "SourcePackages").is_symlink()), None)
            if source:
                if build_activity(include_ide=True) or path_in_use(source):
                    print("Xcode cache preparation deferred: existing packages are in use.")
                    return
                seed.parent.mkdir(parents=True, exist_ok=True)
                try:
                    clonefile(source, seed)
                except OSError as error:
                    print("Could not seed shared packages from " + str(source) + ": " + str(error))
        for directory in directories:
            make_packages_private(paths, directory)
        suffix = Path("PodHaven.xcodeproj/project.xcworkspace/xcuserdata") / (getpass.getuser() + ".xcuserdatad/WorkspaceSettings.xcsettings")
        source, target = paths["primary"] / suffix, root / suffix
        if source.is_file() and not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    result = sweep(root, apply=True)
    print("Xcode preparation complete; removed " + str(len(result["removed"])) + " orphan cache(s), deferred " + str(len(result["deferred"])) + ".")


def diagnose_xcode(root):
    if sys.platform != "darwin" or not (root / "PodHaven.xcodeproj").is_dir():
        return {"available": False}
    paths = layout(root)
    local_dd = checkout_cache(paths, paths["root"])
    agent = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    loaded = subprocess.run(["launchctl", "print", "gui/" + str(os.getuid()) + "/" + LABEL],
                            capture_output=True, timeout=15).returncode == 0
    return {"available": True, "derived_data": str(local_dd), "shared_packages": str(paths["packages"]),
            "packages_private": not (local_dd / "SourcePackages").is_symlink(),
            "last_cleanup": read_json(paths["state"] / "cleanup.json"),
            "cleanup_error": read_json(paths["primary"] / ".cache/worktree-cleanup/last-error.json"),
            "agent_plist": str(agent), "agent_installed": agent.is_file(), "agent_loaded": loaded}


def xcode_health(root):
    report = dict(diagnose_xcode(root), issues=[], notices=[])
    if report["available"]:
        if not report["packages_private"]:
            report["issues"].append("Xcode packages are shared with other checkouts; run bin/prep-worktree.")
        if not report["agent_loaded"]:
            report["notices"].append("Hourly cleanup is not loaded; run bin/install-cleanup-agent in the primary checkout.")
        if report["cleanup_error"]:
            report["issues"].append("Automatic cleanup failed; inspect cleanup_error in bin/doctor-xcode --json.")
        for item in (report["last_cleanup"] or {}).get("deferred", []):
            report["notices"].append("Cleanup deferred: " + item["path"] + ": " + item["reason"])
    return report


def install_agent(root):
    if sys.platform != "darwin":
        print("Hourly Xcode cleanup is macOS-only.")
        return
    paths = layout(root)
    if paths["primary"] != root.resolve():
        raise ValueError("Install the cleanup agent from the primary checkout")
    python = Path.home() / ".local/bin/python3"
    if not os.access(python, os.X_OK):
        raise RuntimeError("Missing the default Python " + str(python) + "; run `uv python install --default`")
    destination = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    # macOS pins a login item to its program's signature, which Apple's shell keeps across Python updates.
    value = {"Label": LABEL, "ProgramArguments": ["/bin/sh", "-c", 'exec "$0" "$@"', str(python),
                                                  str(root / "bin/prune-worktree-caches"), "--apply", "--quiet"],
             "WorkingDirectory": str(root), "StartInterval": 3600, "RunAtLoad": True,
             "ProcessType": "Background", "LowPriorityIO": True,
             "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"},
             "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"}
    content = plistlib.dumps(value)
    domain = "gui/" + str(os.getuid())
    changed = not destination.exists() or destination.read_bytes() != content
    loaded = subprocess.run(["launchctl", "print", domain + "/" + LABEL], capture_output=True).returncode == 0
    if changed:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(".tmp")
        temporary.write_bytes(content)
        temporary.replace(destination)
        if loaded:
            subprocess.run(["launchctl", "bootout", domain + "/" + LABEL], check=True)
            # bootout returns while a running job stops, and bootstrap fails until launchd has removed it.
            timeout = 30
            deadline = time.monotonic() + timeout
            while subprocess.run(["launchctl", "print", domain + "/" + LABEL], capture_output=True).returncode == 0:
                if time.monotonic() > deadline:
                    raise RuntimeError("launchd did not stop " + LABEL + " within " + str(timeout) + " seconds")
                time.sleep(0.2)
            loaded = False
    if not loaded:
        subprocess.run(["launchctl", "bootstrap", domain, str(destination)], check=True)
    print("Hourly cleanup agent installed: " + str(destination))
