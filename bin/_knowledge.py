"""Local knowledge tools. Python standard library only; no shell-wide settings."""

import fcntl
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ("post-checkout", "post-commit", "post-merge", "post-rewrite")
TESTED_QMD = "2.1.0"


def stamp():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def git_environment():
    selectors = {"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
                 "GIT_PREFIX", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"}
    return {key: value for key, value in os.environ.items() if key not in selectors}


def git(*args, root=ROOT, optional=False):
    result = subprocess.run(["git", "-C", str(root), *args], env=git_environment(), text=True, capture_output=True)
    if optional and result.returncode == 1:
        return ""
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip()


def setting(name):
    return git("config", "--local", "--get", "knowledge." + name, optional=True)


def cache(root=ROOT):
    return root / ".cache" / "qmd"


def read_json(path, default=None):
    if not path.exists():
        return {} if default is None else default
    return json.loads(path.read_text())


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    rendered = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path.exists() and path.read_text() == rendered:
        return
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(rendered)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def lock_file(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield stream


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) or
               (pattern.startswith("**/") and fnmatch.fnmatchcase(path, pattern[3:]))
               for pattern in patterns)


def config(include_local=True):
    shared = read_json(ROOT / ".config/knowledge.json")
    if shared.get("schema_version") != 1 or not isinstance(shared.get("collections"), dict):
        raise ValueError("Expected schema_version 1 and collections in .config/knowledge.json")
    rendered = {"collections": {}}
    for name, collection in shared["collections"].items():
        if collection.get("pattern") != "**/*.md":
            raise ValueError("This foundation fingerprints Markdown collections with pattern **/*.md")
        path = (ROOT / collection["path"]).resolve()
        if not path.is_relative_to(ROOT):
            raise ValueError("Shared collection paths must stay inside the checkout; use knowledge.homeMemoryPath for home notes")
        if not path.is_dir():
            raise ValueError("Collection directory is missing: " + str(path))
        if set(collection) - {"path", "pattern", "ignore", "context", "includeByDefault"}:
            raise ValueError("Unsupported collection setting: " + name)
        if "includeByDefault" in collection and not isinstance(collection["includeByDefault"], bool):
            raise ValueError("includeByDefault must be a boolean: " + name)
        rendered["collections"][name] = dict(collection, path=str(path))
    warnings = []
    home = setting("homeMemoryPath") if include_local else ""
    if home:
        path = Path(home).expanduser()
        if not path.is_absolute():
            raise ValueError("knowledge.homeMemoryPath must be absolute")
        if path.is_dir():
            rendered["collections"]["home-memory"] = {
                "path": str(path.resolve()), "pattern": "**/*.md",
                "context": {"/": "Optional personal guidance across projects. Confirm its scope before applying it."},
            }
        else:
            warnings.append("Home memory is missing; skipped: " + str(path))
    return rendered, warnings


def environment():
    return dict(os.environ, QMD_CONFIG_DIR=str(ROOT / ".config/qmd"),
                XDG_CACHE_HOME=str(ROOT / ".cache"), INDEX_PATH=str(cache() / "index.sqlite"))


def qmd_tool():
    requested = setting("qmdPath")
    command = shutil.which(requested or "qmd")
    if requested and not command:
        raise ValueError("knowledge.qmdPath is not executable: " + requested)
    if not command:
        return None, None
    result = subprocess.run([command, "--version"], cwd=ROOT, env=environment(),
                            text=True, capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError("QMD is installed but --version failed: " + result.stderr.strip())
    return command, result.stdout.strip()


def snapshot(rendered, version):
    digest = hashlib.sha256(json.dumps([rendered, version], sort_keys=True).encode())
    counts = {}
    for name, collection in sorted(rendered["collections"].items()):
        root = Path(collection["path"])
        count = 0
        seen = set()
        def scan_error(error):
            raise error
        for directory, directories, files in os.walk(root, followlinks=True, onerror=scan_error):
            resolved = Path(directory).resolve()
            if resolved in seen:
                directories[:] = []
                continue
            seen.add(resolved)
            directories[:] = sorted(d for d in directories if d not in {
                ".git", ".cache", "node_modules", "vendor", "dist", "build"})
            for filename in sorted(files):
                if not filename.endswith(".md"):
                    continue
                path = Path(directory) / filename
                relative = path.relative_to(root).as_posix()
                if matches(relative, collection.get("ignore", [])):
                    continue
                content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
                digest.update(json.dumps([name, relative, content_hash]).encode())
                count += 1
        counts[name] = count
    return digest.hexdigest(), counts


def shared_models(root=ROOT):
    primary = primary_checkout(root)
    if primary:
        existing = cache(primary) / "models"
        if existing.is_dir():
            return existing.resolve()
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", root=root))
    return common / "knowledge" / "models"


def primary_checkout(root):
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", root=root)).resolve()
    current = Path(git("rev-parse", "--absolute-git-dir", root=root)).resolve()
    if common == current:
        return root.resolve()
    recorded = git("config", "--local", "--get", "knowledge.primaryWorktree", root=root, optional=True)
    if recorded and Path(recorded).is_dir():
        candidate = Path(recorded).resolve()
        try:
            candidate_common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", root=candidate)).resolve()
            if candidate_common == common and Path(git("rev-parse", "--show-toplevel", root=candidate)).resolve() == candidate:
                return candidate
        except RuntimeError:
            pass
    output = subprocess.check_output(["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"], env=git_environment())
    first = output.split(b"\0\0", 1)[0].split(b"\0")
    if b"bare" in first:
        return None
    return Path(os.fsdecode(first[0][len(b"worktree "):]))


def prepare(root):
    root = root.resolve()
    if Path(git("rev-parse", "--show-toplevel", root=root)).resolve() != root:
        raise ValueError("Expected a Git checkout root: " + str(root))
    primary = primary_checkout(root)
    if primary and primary.resolve() == root:
        git("config", "--local", "knowledge.primaryWorktree", str(root), root=root)
    models = shared_models(root)
    models.mkdir(parents=True, exist_ok=True)
    local = cache(root) / "models"
    local.parent.mkdir(parents=True, exist_ok=True)
    if not local.exists() and not local.is_symlink():
        local.symlink_to(os.path.relpath(models, local.parent), target_is_directory=True)
    elif local.resolve() != models.resolve():
        print("Preserved existing model cache: " + str(local))
    from _worktrees import prepare_xcode
    prepare_xcode(root)
    if not shutil.which("direnv"):
        print("direnv absent: environment approval skipped.")
        return
    envrc = root / ".envrc"
    if not envrc.exists():
        return
    if primary and primary.resolve() != root and (primary / ".envrc").is_file():
        result = subprocess.run(["direnv", "status", "--json"], cwd=primary, text=True, capture_output=True)
        try:
            found = json.loads(result.stdout).get("state", {}).get("foundRC") or {}
        except ValueError:
            found = {}
        if (result.returncode == 0 and found.get("allowed") == 0 and
                Path(found.get("path", "")).resolve() == (primary / ".envrc").resolve() and
                envrc.read_bytes() == (primary / ".envrc").read_bytes()):
            subprocess.run(["direnv", "allow", str(envrc)], check=True)
            print("Allowed the worktree environment matching the trusted primary checkout.")
            return
    print("Environment file preserved. After reviewing it, use direnv allow if needed.")


def hooks_path():
    path = Path(git("rev-parse", "--git-path", "hooks"))
    return path if path.is_absolute() else ROOT / path


def install_hooks():
    mode = setting("hooks") or "bundled"
    if mode not in {"bundled", "external"}:
        raise ValueError("knowledge.hooks must be bundled or external")
    active = hooks_path()
    bundled = ROOT / "bin/hooks"
    if mode == "external":
        print("Preserved external hooks: " + str(active))
        print("Verify all four forwarding calls as described in docs/development-workflow.md.")
        return
    configured = git("config", "--get", "core.hooksPath", optional=True)
    existing = active.is_dir() and any(p.is_file() and os.access(p, os.X_OK)
                                      and not p.name.endswith(".sample") for p in active.iterdir())
    if active.resolve() != bundled.resolve() and (configured or existing):
        raise RuntimeError("Existing hooks preserved at " + str(active) +
                           ". Integrate bin/knowledge-hook, then set git config --local knowledge.hooks external. See docs/development-workflow.md#existing-hooks")
    for event in EVENTS:
        if not os.access(bundled / event, os.X_OK):
            raise RuntimeError("Missing executable hook: bin/hooks/" + event)
    git("config", "--local", "core.hooksPath", "bin/hooks")
    print("Active hooks: bin/hooks")


def worker_active():
    path = cache() / "worker.lock"
    if not path.exists():
        return False
    with path.open("r") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
        except BlockingIOError:
            return True


def enqueue(force=False):
    # The short scheduling lock protects the last-check/unlock handoff. A request
    # can never arrive between a worker deciding to exit and releasing its lock.
    with lock_file(cache() / "schedule.lock"):
        queue = read_json(cache() / "queue.json", {"requested": 0, "completed": 0})
        queue["requested"] += 1
        queue["force"] = queue.get("force", False) or force
        atomic_json(cache() / "queue.json", queue)
        fd = os.open(cache() / "worker.lock", os.O_CREAT | os.O_RDWR, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return queue["requested"]
            log_path = cache() / "index.log"
            if log_path.exists() and log_path.stat().st_size > 1_000_000:
                log_path.replace(cache() / "index.previous.log")
            with log_path.open("a") as log:
                subprocess.Popen([sys.executable, str(ROOT / "bin/qmd-index"), "--worker", str(fd)],
                                 cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 pass_fds=(fd,), start_new_session=True)
        finally:
            # Do not explicitly unlock: the child inherits this open file description.
            os.close(fd)
        return queue["requested"]


def refresh(force):
    previous = read_json(cache() / "state.json")
    result = {"finished_at": stamp(), "status": "failed", "exit_code": 1,
              "last_success": previous.get("last_success")}
    changed_during_run = False
    try:
        rendered, warnings = config()
        for warning in warnings:
            print(warning, flush=True)
        atomic_json(ROOT / ".config/qmd/index.yml", rendered)
        tool, version = qmd_tool()
        result["qmd_version"] = version
        if not tool:
            result.update(status="skipped", exit_code=0, message="QMD absent: local search skipped.")
        else:
            before, counts = snapshot(rendered, version)
            prior = previous.get("last_success") or {}
            unchanged = (not force and prior.get("fingerprint") == before and
                         (cache() / "index.sqlite").is_file() and previous.get("status") == "success")
            if not unchanged:
                for command in ("update", "embed"):
                    subprocess.run([tool, command], cwd=ROOT, env=environment(), check=True)
            after_config, _ = config()
            after, _ = snapshot(after_config, version)
            changed_during_run = before != after
            result.update(status="success", exit_code=0, message="Unchanged inputs; refresh skipped." if unchanged else "Index refreshed.",
                          last_success={"at": stamp(), "fingerprint": before, "counts": counts, "qmd_version": version})
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        result["message"] = str(error)
    result["finished_at"] = stamp()
    atomic_json(cache() / "state.json", result)
    print(result["message"], flush=True)
    return result["exit_code"], changed_during_run


def worker(fd):
    with os.fdopen(fd, "a") as running:
        while True:
            with lock_file(cache() / "schedule.lock"):
                queue = read_json(cache() / "queue.json")
                ticket, force = queue["requested"], queue.pop("force", False)
                atomic_json(cache() / "queue.json", queue)
            code, changed = refresh(force)
            with lock_file(cache() / "schedule.lock"):
                queue = read_json(cache() / "queue.json")
                if changed and code == 0:
                    if queue["requested"] == ticket:
                        queue["requested"] += 1
                else:
                    queue.update(completed=ticket, exit_code=code)
                atomic_json(cache() / "queue.json", queue)
                if queue["requested"] == ticket:
                    fcntl.flock(running, fcntl.LOCK_UN)
                    return code


def wait_for(ticket):
    while True:
        queue = read_json(cache() / "queue.json")
        if queue.get("completed", 0) >= ticket:
            state = read_json(cache() / "state.json")
            print(state.get("message", "Refresh finished."))
            if queue.get("exit_code"):
                print("Details: " + str(cache() / "index.log"), file=sys.stderr)
            return queue.get("exit_code", 1)
        if not worker_active():
            # Re-read after observing the released lock to avoid an exit race.
            if read_json(cache() / "queue.json").get("completed", 0) >= ticket:
                continue
            print("Index worker stopped before completing. Run bin/qmd-index --force; inspect .cache/qmd/index.log.", file=sys.stderr)
            return 1
        time.sleep(0.05)


def diagnose():
    report = {"root": str(ROOT), "hooks_path": str(hooks_path()), "hooks_mode": setting("hooks") or "bundled",
              "index": str(cache() / "index.sqlite"), "models": str((cache() / "models").resolve()),
              "shared_models": str(shared_models()), "worker_running": worker_active(),
              "tested_qmd": TESTED_QMD, "python": sys.version.split()[0], "issues": [], "notices": []}
    report["direnv_available"] = bool(shutil.which("direnv"))
    report["git_version"] = git("--version")
    report["primary_checkout"] = str(primary_checkout(ROOT))
    for command, argument in (("direnv", "version"), ("shellcheck", "--version")):
        if shutil.which(command):
            result = subprocess.run([command, argument], cwd=ROOT, text=True, capture_output=True, timeout=15)
            report[command + "_version"] = result.stdout.strip()
            if result.returncode:
                report["issues"].append(command + " is installed but its version check failed.")
        else:
            report[command + "_version"] = None
    if not report["shellcheck_version"]:
        report["notices"].append("ShellCheck absent: install it before running bin/check.")
    active = hooks_path()
    if report["hooks_mode"] == "bundled":
        if active.resolve() != (ROOT / "bin/hooks").resolve() or any(not os.access(active / e, os.X_OK) for e in EVENTS):
            report["issues"].append("Bundled hooks are not active. Run bin/setup.")
    elif report["hooks_mode"] == "external":
        observations = read_json(cache() / "hooks.json")
        report["observed_hooks"] = observations
        missing = [e for e in EVENTS if observations.get(e, {}).get("path") != str(active)]
        if missing:
            report["issues"].append("External forwarding not yet observed for: " + ", ".join(missing) + ". Follow docs/development-workflow.md#existing-hooks.")
        report["notices"].append("Hook observations record past runs; re-verify after changing a hook manager.")
    else:
        report["issues"].append("Invalid knowledge.hooks setting.")
    try:
        rendered, warnings = config()
        report["notices"].extend(warnings)
        report["collections"] = {k: v["path"] for k, v in rendered["collections"].items()}
        tool, version = qmd_tool()
        report.update(qmd=tool, qmd_version=version)
        state = read_json(cache() / "state.json")
        report["last_refresh"] = state or None
        if not tool:
            report["freshness"] = "unavailable"
            report["notices"].append("QMD absent: search is optional. Use the Markdown source files.")
        else:
            fingerprint, report["document_counts"] = snapshot(rendered, version)
            last = state.get("last_success") or {}
            if not last:
                report["freshness"] = "unknown"
            elif (last.get("fingerprint") == fingerprint and (cache() / "index.sqlite").is_file()
                  and read_json(ROOT / ".config/qmd/index.yml") == rendered):
                report["freshness"] = "current"
            else:
                report["freshness"] = "stale"
            if report["freshness"] != "current" or state.get("status") == "failed":
                report["issues"].append("Search needs refresh or recovery. Run bin/qmd-index; inspect .cache/qmd/index.log on failure.")
            if version and TESTED_QMD not in version:
                report["notices"].append("This QMD version differs from the tested version; run the real-QMD smoke check before relying on compatibility.")
        models = cache() / "models"
        if not models.is_dir():
            report["issues"].append("Model cache missing or broken. Inspect .cache/qmd/models, then run bin/prep-worktree.")
        elif models.resolve() != shared_models().resolve():
            report["notices"].append("Existing model cache preserved; it is not the default shared cache.")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["freshness"] = "unknown"
        report["issues"].append(str(error))
    try:
        from _worktrees import diagnose_xcode
        report["xcode"] = diagnose_xcode(ROOT)
        if report["xcode"]["available"]:
            if not report["xcode"]["packages_link_valid"]:
                report["issues"].append("Xcode package link needs attention; run bin/prep-worktree.")
            if not report["xcode"]["agent_loaded"]:
                report["notices"].append("Hourly cleanup is not loaded; run bin/install-cleanup-agent in the primary checkout.")
            if report["xcode"]["cleanup_error"]:
                report["issues"].append("Automatic cleanup failed; inspect xcode.cleanup_error.")
            for item in (report["xcode"].get("last_cleanup") or {}).get("deferred", []):
                report["notices"].append("Cleanup deferred: " + item["path"] + ": " + item["reason"])
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["issues"].append("Xcode diagnostics failed: " + str(error))
    return report


def cli(action):
    args = sys.argv[1:]
    try:
        if sys.version_info < (3, 9):
            raise RuntimeError("Python 3.9 or later is required")
        if Path(git("rev-parse", "--show-toplevel")).resolve() != ROOT:
            raise ValueError("Copy the starter into the target checkout root before running its tools")
        if action == "prep":
            if len(args) > 1:
                raise ValueError("Usage: bin/prep-worktree [checkout-root]")
            prepare(Path(args[0]) if args else ROOT)
            return 0
        if action == "setup":
            if args:
                raise ValueError("Usage: bin/setup")
            config()  # Validate before changing local setup.
            install_hooks()
            alias = '!f() { "$(git rev-parse --show-toplevel)/bin/knowledge" "$@"; }; f'
            existing_alias = git("config", "--get", "alias.knowledge", optional=True)
            if not existing_alias:
                git("config", "--local", "alias.knowledge", alias)
            elif existing_alias != alias:
                print("Preserved existing git knowledge alias; use bin/knowledge directly.")
            prepare(ROOT)
            return wait_for(enqueue())
        if action == "index":
            if len(args) == 2 and args[0] == "--worker":
                return worker(int(args[1]))
            if any(a not in {"--background", "--force"} for a in args):
                raise ValueError("Usage: bin/qmd-index [--background] [--force]")
            ticket = enqueue(force="--force" in args)
            return 0 if "--background" in args else wait_for(ticket)
        if action == "doctor":
            if args not in ([], ["--json"]):
                raise ValueError("Usage: bin/doctor [--json]")
            report = diagnose()
            if args:
                print(json.dumps(report, indent=2))
            else:
                for key in ("root", "primary_checkout", "hooks_mode", "hooks_path", "git_version", "python", "qmd_version", "tested_qmd", "direnv_version", "shellcheck_version", "index", "models", "shared_models", "worker_running", "freshness", "collections", "last_refresh"):
                    print(key + ": " + str(report.get(key)))
                print("xcode: " + json.dumps(report.get("xcode")))
                for message in report["notices"] + report["issues"]:
                    print(message)
            return bool(report["issues"])
        if action == "hook":
            if not args or args[0] not in EVENTS:
                raise ValueError("Usage: bin/knowledge-hook <post-checkout|post-commit|post-merge|post-rewrite> [hook arguments]")
            event = args[0]
            with lock_file(cache() / "hooks.lock"):
                observed = read_json(cache() / "hooks.json")
                observed[event] = {"at": stamp(), "path": str(hooks_path())}
                atomic_json(cache() / "hooks.json", observed)
            if event == "post-checkout" and len(args) >= 4 and args[3] == "1" and args[1] and set(args[1]) == {"0"}:
                prepare(ROOT)
            enqueue()
            return 0
        if action == "knowledge":
            allowed = {"search", "query", "vsearch", "get", "multi-get", "ls", "status", "--version"}
            if not args or (args[0] not in allowed and args != ["context", "list"]):
                raise ValueError("Usage: bin/knowledge <search|query|vsearch|get|multi-get|ls|status> [arguments]. Edit .config/knowledge.json for collections; use bin/qmd-index for refreshes.")
            if "--index" in args or any(a.startswith("--index=") for a in args):
                raise ValueError("This command uses the checkout's own index; named indexes are not supported")
            rendered, warnings = config()
            for warning in warnings:
                print(warning, file=sys.stderr)
            if read_json(ROOT / ".config/qmd/index.yml") != rendered:
                raise RuntimeError("Search configuration is missing or changed. Run bin/qmd-index first.")
            tool, version = qmd_tool()
            if not tool:
                raise RuntimeError("QMD is not installed. Read or search the Markdown source files directly.")
            fingerprint, _ = snapshot(rendered, version)
            state = read_json(cache() / "state.json")
            if (state.get("last_success") or {}).get("fingerprint") != fingerprint or state.get("status") != "success":
                print("Warning: search freshness is stale or unknown. Run bin/qmd-index; verify results against source files.", file=sys.stderr)
            return subprocess.run([tool, *args], cwd=ROOT, env=environment()).returncode
        raise ValueError("Unknown command")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        if action == "hook":
            print("Knowledge hook failed; Git can continue. Run bin/doctor.", file=sys.stderr)
            return 0
        return 1
