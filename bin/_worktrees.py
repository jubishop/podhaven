"""Prepare Xcode caches and reclaim verified orphan caches on macOS."""

import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
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


def cache_owner(folder):
    if folder.is_symlink() or not folder.is_dir():
        return None
    try:
        workspace = Path(plistlib.loads((folder / "info.plist").read_bytes())["WorkspacePath"])
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
        if not source.is_relative_to(alias) or not alias.is_symlink() or alias.resolve() != packages:
            raise ValueError("Shared metadata references an unshared cache path")
        relative = source.relative_to(alias)
        if ".." in relative.parts:
            raise ValueError("Shared metadata contains a path traversal")
        target = (packages / relative).resolve()
        if not target.is_relative_to(packages) or not target.exists() or not source.exists() or not os.path.samefile(source, target):
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
        for folder in sorted(paths["derived"].glob("PodHaven-*")):
            owner = cache_owner(folder)
            if owner is None or str(owner) in live or owner.exists():
                continue
            if str(owner) not in known and not owner.is_relative_to(paths["primary"] / "worktrees"):
                report["deferred"].append({"path": str(folder), "reason": "Ownership by this clone is unverified"})
                continue
            report["candidates"].append(str(folder))
            try:
                if build_activity() or path_in_use(folder):
                    raise ValueError("Build or open-file activity; automatic cleanup will retry")
                packages = folder / "SourcePackages"
                if packages.exists() and (not packages.is_symlink() or packages.resolve() != paths["packages"]):
                    raise ValueError("Preserved an independent package cache")
                state = paths["packages"] / "workspace-state.json"
                before = state.read_bytes() if state.exists() else None
                parsed = json.loads(before) if before is not None else {}
                updated, changed = artifact_references(parsed, folder, paths["packages"])
                if changed and (build_activity(include_ide=True) or path_in_use(paths["packages"])):
                    raise ValueError("Shared metadata needs repair; waiting for Xcode and package users to close")
                if not apply:
                    continue
                # Repeat ownership, activity, and metadata checks immediately before mutation.
                if owner.exists() or str(owner) in registered_worktrees(root) or cache_owner(folder) != owner:
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
                (folder / "info.plist").unlink()
                folder.rmdir()
                report["removed"].append(str(folder))
                report["removed_cache_bytes"] += size
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                report["deferred"].append({"path": str(folder), "reason": str(error)})
        if apply:
            atomic_json(paths["state"] / "cleanup.json", report)
    return report


def prepare_xcode(root):
    if sys.platform != "darwin" or not (root / "PodHaven.xcodeproj").is_dir():
        return
    paths = layout(root)
    with maintenance_lock(paths):
        known = set(read_json(paths["state"] / "worktrees.json", [])) | registered_worktrees(root)
        atomic_json(paths["state"] / "worktrees.json", sorted(known))
        primary_dd = paths["derived"] / ("PodHaven-" + xcode_hash(paths["primary"] / "PodHaven.xcodeproj"))
        local_dd = paths["derived"] / ("PodHaven-" + xcode_hash(root / "PodHaven.xcodeproj"))
        shared = paths["packages"]
        if not shared.exists():
            seed = next((p / "SourcePackages" for p in (primary_dd, local_dd)
                         if (p / "SourcePackages").is_dir() and not (p / "SourcePackages").is_symlink()), None)
            if seed:
                if build_activity(include_ide=True) or path_in_use(seed):
                    print("Xcode cache preparation deferred: existing packages are in use.")
                    return
                shared.parent.mkdir(parents=True, exist_ok=True)
                seed.rename(shared)
                seed.symlink_to(shared, target_is_directory=True)
            else:
                shared.mkdir(parents=True)
        for directory in {primary_dd, local_dd}:
            directory.mkdir(parents=True, exist_ok=True)
            link = directory / "SourcePackages"
            if not link.exists() and not link.is_symlink():
                link.symlink_to(shared, target_is_directory=True)
            elif not link.is_symlink() or link.resolve() != shared:
                print("Preserved existing SourcePackages; inspect with bin/doctor: " + str(link))
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
    local_dd = paths["derived"] / ("PodHaven-" + xcode_hash(root / "PodHaven.xcodeproj"))
    link = local_dd / "SourcePackages"
    agent = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    loaded = subprocess.run(["launchctl", "print", "gui/" + str(os.getuid()) + "/" + LABEL],
                            capture_output=True, timeout=15).returncode == 0
    return {"available": True, "derived_data": str(local_dd), "shared_packages": str(paths["packages"]),
            "packages_link_valid": link.is_symlink() and link.resolve() == paths["packages"] and link.is_dir(),
            "last_cleanup": read_json(paths["state"] / "cleanup.json"),
            "cleanup_error": read_json(paths["primary"] / ".cache/worktree-cleanup/last-error.json"),
            "agent_plist": str(agent), "agent_installed": agent.is_file(), "agent_loaded": loaded}


def install_agent(root):
    if sys.platform != "darwin":
        print("Hourly Xcode cleanup is macOS-only.")
        return
    paths = layout(root)
    if paths["primary"] != root.resolve():
        raise ValueError("Install the cleanup agent from the primary checkout")
    destination = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    value = {"Label": LABEL, "ProgramArguments": [sys.executable, str(root / "bin/prune-worktree-caches"), "--apply", "--quiet"],
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
            loaded = False
    if not loaded:
        subprocess.run(["launchctl", "bootstrap", domain, str(destination)], check=True)
    print("Hourly cleanup agent installed: " + str(destination))
