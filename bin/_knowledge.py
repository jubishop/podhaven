"""Local knowledge tools. Python standard library only; no shell-wide settings.

Code outside this checkout may import Knowledge to run the search engine on a root of its own."""

import fcntl
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ("post-checkout", "post-commit", "post-merge", "post-rewrite", "pre-push")
# The home repository's setup installs these tools on the Mac every adopter runs on, so a missing one means it broke.
REQUIRED_TOOLS = "docs/foundation/knowledge-search.md#required-tools"
DIRENV_MISSING = "direnv is required for this checkout's .envrc but not installed. Restore it; see " + REQUIRED_TOOLS
SHELLCHECK_MISSING = "ShellCheck is required by bin/check but not installed. Restore it; see " + REQUIRED_TOOLS


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


def collection_files(collection):
    root = Path(collection["path"])
    if collection["pattern"] != "**/*.md":
        # A missing file indexes nothing, as in QMD, so sparse copies of a checkout still search.
        if (root / collection["pattern"]).is_file():
            yield root / collection["pattern"]
        return
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
            if filename.endswith(".md"):
                yield Path(directory) / filename


def snapshot(rendered, version):
    # QMD's Git suffix can come from a surrounding repository, not its own build.
    # Keep the release (including prerelease/build metadata) as the stable input.
    version = re.sub(r" \([0-9a-fA-F]{4,64}\)$", "", version)
    digest = hashlib.sha256(json.dumps([rendered, version], sort_keys=True).encode())
    counts = {}
    for name, collection in sorted(rendered["collections"].items()):
        root = Path(collection["path"])
        count = 0
        for path in collection_files(collection):
            relative = path.relative_to(root).as_posix()
            if matches(relative, collection.get("ignore", [])):
                continue
            content_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            digest.update(json.dumps([name, relative, content_hash]).encode())
            count += 1
        counts[name] = count
    return digest.hexdigest(), counts


def shared_models(root=ROOT):
    return Path.home() / ".cache" / "qmd" / "models"


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
    return checkouts(root)[0]


def checkouts(root=ROOT):
    """List the clone's checkout roots, the primary first; a bare repository's entry is None."""
    output = subprocess.check_output(["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"], env=git_environment())
    records = [record.split(b"\0") for record in output.split(b"\0\0") if record.startswith(b"worktree ")]
    return [None if b"bare" in fields else Path(os.fsdecode(fields[0][len(b"worktree "):])) for fields in records]


def prepare(root):
    root = root.resolve()
    if Path(git("rev-parse", "--show-toplevel", root=root)).resolve() != root:
        raise ValueError("Expected a Git checkout root: " + str(root))
    primary = primary_checkout(root)
    if primary and primary.resolve() == root:
        git("config", "--local", "knowledge.primaryWorktree", str(root), root=root)
    Knowledge(root).prepare_models()
    envrc = root / ".envrc"
    if not envrc.exists():
        return
    if not shutil.which("direnv"):
        raise RuntimeError(DIRENV_MISSING)
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


def setup_application(root):
    """Run the project-owned dependency setup in a checkout; return its exit status."""
    application = root / "bin/setup-application"
    if not application.exists():
        return 0
    if not os.access(application, os.X_OK):
        raise RuntimeError("bin/setup-application must be executable")
    code = subprocess.run([str(application)], cwd=root, env=git_environment()).returncode
    if code:
        print("bin/setup-application failed in " + str(root) + " (exit " + str(code) + "); run it there again.",
              file=sys.stderr)
    return code


class Knowledge:
    """Keep a root's Markdown collections searchable with QMD, and set up and diagnose a checkout's tools.

    By default it serves the checkout holding this file. Code elsewhere passes its own root and may pass:

    - cache: the folder where QMD keeps its index and models in a qmd folder, as under XDG_CACHE_HOME; the
      root's .cache by default.
    - config: the folder holding knowledge.json, which defines the collections, and QMD's configuration in a qmd
      folder; the root's .config by default.
    - worker: the command that runs the index worker. The engine appends the worker's lock descriptor, which the
      command passes to worker().

    Settings come from the root's local Git configuration. A subclass that reads them elsewhere overrides setting(),
    and setting_name() to name them in messages as its reader sets them. It may also name its own commands and pages
    below, which messages tell the reader to run or read.
    """

    doctor_command = "bin/doctor"
    refresh_command = "bin/qmd-index"
    prepare_command = "bin/prep-worktree"
    required_tools_page = REQUIRED_TOOLS
    models_page = "docs/foundation/knowledge-search.md#worktrees-and-models"

    def __init__(self, root=ROOT, cache=None, config=None, worker=None):
        self.root = Path(root).resolve()
        self.cache_home = Path(cache).resolve() if cache else self.root / ".cache"
        self.config_home = Path(config).resolve() if config else self.root / ".config"
        self.cache = self.cache_home / "qmd"
        self.qmd_config = self.config_home / "qmd"
        self.worker_command = list(worker or [sys.executable, str(self.root / "bin/qmd-index"), "--worker"])

    def setting(self, name):
        return git("config", "--local", "--get", "knowledge." + name, root=self.root, optional=True)

    def setting_name(self, name):
        """Name a setting in a message as the reader sets it."""
        return "knowledge." + name

    def shown(self, path):
        """Name a path in a message, relative to the root when inside it."""
        return path.relative_to(self.root).as_posix() if path.is_relative_to(self.root) else str(path)

    def repair(self):
        return "Run " + self.doctor_command + " and " + self.refresh_command + "."

    def config(self):
        source = self.config_home / "knowledge.json"
        shared = read_json(source)
        if shared.get("schema_version") != 1 or not isinstance(shared.get("collections"), dict):
            raise ValueError("Expected schema_version 1 and collections in " + self.shown(source))
        rendered = {"collections": {}}
        for name, collection in shared["collections"].items():
            pattern = collection.get("pattern")
            # A literal file name matches only that file in the collection directory,
            # so a root README collection never reaches nested docs or worktrees.
            single_file = pattern != "**/*.md"
            if single_file and not (isinstance(pattern, str) and re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]*\.md", pattern)):
                raise ValueError("Collection " + name + " needs pattern **/*.md or one Markdown file name in its directory")
            path = (self.root / collection["path"]).resolve()
            if not path.is_relative_to(self.root):
                raise ValueError("Collection paths must stay inside the checkout: " + name)
            if not path.is_dir():
                raise ValueError("Collection directory is missing: " + str(path))
            if set(collection) - {"path", "pattern", "ignore", "context"}:
                raise ValueError("Unsupported collection setting: " + name)
            rendered["collections"][name] = dict(collection, path=str(path))
        return rendered

    def environment(self):
        return dict(git_environment(), QMD_CONFIG_DIR=str(self.qmd_config),
                    XDG_CACHE_HOME=str(self.cache_home), INDEX_PATH=str(self.cache / "index.sqlite"))

    def configuration_matches(self, rendered):
        path = self.qmd_config / "index.yml"
        return path.is_file() and path.read_text() == json.dumps(rendered, indent=2, sort_keys=True) + "\n"

    @contextmanager
    def command_environment(self):
        with tempfile.TemporaryDirectory(prefix="command-", dir=self.cache) as temporary:
            path = Path(temporary)
            (path / "index.yml").write_bytes((self.qmd_config / "index.yml").read_bytes())
            yield dict(self.environment(), QMD_CONFIG_DIR=str(path))

    def qmd_tool(self):
        requested = self.setting("qmdPath")
        command = shutil.which(requested or "qmd")
        if requested and not command:
            raise ValueError(self.setting_name("qmdPath") + " is not executable: " + requested)
        if not command:
            raise RuntimeError("QMD is required but not installed. Restore it, or point " +
                               self.setting_name("qmdPath") + " at it; see " + self.required_tools_page)
        result = subprocess.run([command, "--version"], cwd=self.root, env=self.environment(),
                                text=True, capture_output=True, timeout=15)
        if result.returncode:
            raise RuntimeError("QMD is installed but --version failed: " + result.stderr.strip())
        return command, result.stdout.strip()

    def prepare_models(self):
        """Link the models folder in QMD's cache folder to the shared models, creating or repairing the link."""
        models = shared_models()
        local = self.cache / "models"
        models.mkdir(parents=True, exist_ok=True)
        if local.resolve() == models.resolve():
            return
        if local.exists() and not local.is_symlink():
            raise ValueError("Move what " + str(local) + " holds into " + str(models) +
                             " and remove it, so it can link to the shared models; see " + self.models_page)
        self.cache.mkdir(parents=True, exist_ok=True)
        # Replacing the link in one rename leaves concurrent setups no gap. The old target stays untouched.
        with tempfile.TemporaryDirectory(prefix="models-", dir=self.cache) as temporary:
            link = Path(temporary) / "models"
            link.symlink_to(models, target_is_directory=True)
            link.replace(local)

    def hooks_path(self):
        path = Path(git("rev-parse", "--git-path", "hooks", root=self.root))
        return path if path.is_absolute() else self.root / path

    def shared_hooks(self, active):
        """Report whether active is another checkout's bin/hooks.

        A clone's checkouts share its core.hooksPath, so it may name one checkout's bin/hooks for all of them."""
        own = (self.root / "bin/hooks").resolve()
        return active.resolve() != own and active.resolve() in {(path / "bin/hooks").resolve()
                                                                for path in checkouts(self.root) if path}

    def shared_hooks_error(self, active):
        """Name the events whose shared hook differs from this checkout's bundled hook, or return None."""
        def matches(event):
            try:
                return (os.access(active / event, os.X_OK) and
                        (active / event).read_bytes() == (self.root / "bin/hooks" / event).read_bytes())
            except OSError:
                return False
        differing = [event for event in EVENTS if not matches(event)]
        if not differing:
            return None
        return (str(active) + ", another checkout's bin/hooks, differs from this checkout's for: " + ", ".join(differing) +
                ". Bring both checkouts to the same hooks; see docs/foundation/knowledge-search.md#shared-hooks")

    def install_hooks(self):
        mode = self.setting("hooks") or "bundled"
        if mode not in {"bundled", "external"}:
            raise ValueError("knowledge.hooks must be bundled or external")
        active = self.hooks_path()
        bundled = self.root / "bin/hooks"
        if mode == "external":
            print("Preserved external hooks: " + str(active))
            print("Verify every forwarding call as described in docs/foundation/knowledge-search.md#existing-hooks.")
            return
        if self.shared_hooks(active):
            error = self.shared_hooks_error(active)
            if error:
                raise RuntimeError(error)
            print("Active hooks: " + str(active))
            return
        configured = git("config", "--get", "core.hooksPath", root=self.root, optional=True)
        existing = active.is_dir() and any(p.is_file() and os.access(p, os.X_OK)
                                          and not p.name.endswith(".sample") for p in active.iterdir())
        if active.resolve() != bundled.resolve() and (configured or existing):
            raise RuntimeError("Existing hooks preserved at " + str(active) +
                               ". Integrate bin/knowledge-hook, then set git config --local knowledge.hooks external. See docs/foundation/knowledge-search.md#existing-hooks")
        for event in EVENTS:
            if not os.access(bundled / event, os.X_OK):
                raise RuntimeError("Missing executable hook: bin/hooks/" + event)
        if not configured:
            git("config", "--local", "core.hooksPath", "bin/hooks", root=self.root)
        print("Active hooks: " + (configured or "bin/hooks"))

    def changes_markdown(self, remote, commit):
        """Report whether pushing commit over the remote's old commit, or as a new ref, changes a Markdown file."""
        known = set(remote) != {"0"} and git("rev-parse", "--verify", "--quiet", remote + "^{commit}",
                                             root=self.root, optional=True)
        # Without renames, a page renamed away still counts as removed.
        if known:
            paths = git("diff", "--no-renames", "--name-only", "-z", remote, commit, root=self.root)
        else:
            paths = git("log", "-m", "--no-renames", "--name-only", "-z", "--format=", commit, "--not", "--remotes",
                        root=self.root)
        return any(path.endswith(".md") for path in paths.split("\0"))

    def check_push(self, updates):
        """Run bin/check --documents-only on each pushed revision that changes Markdown; return the exit status."""
        revisions = {}
        for line in updates.splitlines():
            # Git passes the local ref as typed, such as ":/Fix the index", so only it can hold spaces.
            fields = line.rsplit(" ", 3)
            if (len(fields) != 4 or not fields[0] or not fields[2]
                    or not all(re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", fields[i]) for i in (1, 3))):
                raise ValueError("Unexpected pre-push input: " + line)
            _, local, remote_ref, remote = fields
            commit = set(local) != {"0"} and git("rev-parse", "--verify", "--quiet", local + "^{commit}",
                                                 root=self.root, optional=True)
            if commit and commit not in revisions and self.changes_markdown(remote, commit):
                revisions[commit] = remote_ref
        status = 0
        for commit, remote_ref in revisions.items():
            # Check the pushed revision itself, not the working tree, in a disposable clone with hooks off.
            with tempfile.TemporaryDirectory(prefix="project-starter-push-") as snapshot:
                common = git("rev-parse", "--path-format=absolute", "--git-common-dir", root=self.root)
                git("-c", "core.hooksPath=/dev/null", "clone", "--quiet", "--shared", "--no-checkout", common, snapshot,
                    root=self.root)
                git("-c", "core.hooksPath=/dev/null", "checkout", "--quiet", "--detach", commit, root=Path(snapshot))
                check = Path(snapshot) / "bin/check"
                if not os.access(check, os.X_OK):
                    print("Skipped the document checks for " + commit[:12] + ", which has no bin/check.", file=sys.stderr)
                    continue
                result = subprocess.run([str(check), "--documents-only"], cwd=snapshot, env=git_environment(),
                                        text=True, capture_output=True)
            if result.returncode:
                print("bin/check --documents-only failed for " + commit[:12] + ", pushed to " + remote_ref +
                      ", so Git refused the push:\n" + (result.stderr or result.stdout).rstrip() +
                      "\nFix the pages, commit, and push again.", file=sys.stderr)
                status = 1
        return status

    def pre_push_application(self, arguments, updates):
        """Run the project-owned pre-push hook as Git would run it; return its exit status."""
        application = self.root / "bin/pre-push-application"
        if not application.exists():
            return 0
        if not os.access(application, os.X_OK):
            raise RuntimeError("bin/pre-push-application must be executable")
        return subprocess.run([str(application), *arguments], cwd=self.root, input=updates, text=True).returncode

    def worker_active(self):
        path = self.cache / "worker.lock"
        if not path.exists():
            return False
        with path.open("r") as stream:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return False
            except BlockingIOError:
                return True

    def enqueue(self, force=False):
        # The short scheduling lock protects the last-check/unlock handoff. A request
        # can never arrive between a worker deciding to exit and releasing its lock.
        with lock_file(self.cache / "schedule.lock"):
            queue = read_json(self.cache / "queue.json", {"requested": 0, "completed": 0})
            queue["requested"] += 1
            queue["force"] = queue.get("force", False) or force
            atomic_json(self.cache / "queue.json", queue)
            fd = os.open(self.cache / "worker.lock", os.O_CREAT | os.O_RDWR, 0o600)
            try:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    return queue["requested"]
                log_path = self.cache / "index.log"
                if log_path.exists() and log_path.stat().st_size > 1_000_000:
                    log_path.replace(self.cache / "index.previous.log")
                with log_path.open("a") as log:
                    subprocess.Popen([*self.worker_command, str(fd)],
                                     cwd=self.root, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                     pass_fds=(fd,), start_new_session=True)
            finally:
                # Do not explicitly unlock: the child inherits this open file description.
                os.close(fd)
            return queue["requested"]

    def refresh(self, force):
        previous = read_json(self.cache / "state.json")
        result = {"finished_at": stamp(), "status": "failed", "exit_code": 1,
                  "last_success": previous.get("last_success")}
        changed_during_run = False
        try:
            rendered = self.config()
            atomic_json(self.qmd_config / "index.yml", rendered)
            self.prepare_models()
            tool, version = self.qmd_tool()
            result["qmd_version"] = version
            # Logs append across runtime upgrades; date each section for later triage.
            print(stamp() + " Refresh started with " + version, flush=True)
            before, counts = snapshot(rendered, version)
            prior = previous.get("last_success") or {}
            unchanged = (not force and prior.get("fingerprint") == before and
                         (self.cache / "index.sqlite").is_file() and previous.get("status") == "success")
            if not unchanged:
                # Cleanup drops vectors of replaced or removed pages, which update and embed keep.
                for command in ("update", "embed", "cleanup"):
                    with self.command_environment() as env:
                        subprocess.run([tool, command], cwd=self.root, env=env, check=True)
            after, _ = snapshot(self.config(), version)
            changed_during_run = before != after
            result.update(status="success", exit_code=0,
                          message="Unchanged inputs; refresh skipped." if unchanged else "Index refreshed.",
                          last_success={"at": stamp(), "fingerprint": before, "counts": counts, "qmd_version": version})
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            result["message"] = str(error)
        result["finished_at"] = stamp()
        atomic_json(self.cache / "state.json", result)
        print(result["message"], flush=True)
        return result["exit_code"], changed_during_run

    def worker(self, fd):
        with os.fdopen(fd, "a") as running:
            while True:
                with lock_file(self.cache / "schedule.lock"):
                    queue = read_json(self.cache / "queue.json")
                    ticket, force = queue["requested"], queue.pop("force", False)
                    atomic_json(self.cache / "queue.json", queue)
                code, changed = self.refresh(force)
                with lock_file(self.cache / "schedule.lock"):
                    queue = read_json(self.cache / "queue.json")
                    if changed and code == 0:
                        if queue["requested"] == ticket:
                            queue["requested"] += 1
                    else:
                        queue.update(completed=ticket, exit_code=code)
                    atomic_json(self.cache / "queue.json", queue)
                    if queue["requested"] == ticket:
                        fcntl.flock(running, fcntl.LOCK_UN)
                        return code

    def wait_for(self, ticket, timeout=None, output=None):
        output = output or sys.stdout
        deadline = time.monotonic() + timeout if timeout is not None else None
        while True:
            queue = read_json(self.cache / "queue.json")
            if queue.get("completed", 0) >= ticket and not self.worker_active():
                state = read_json(self.cache / "state.json")
                print(state.get("message", "Refresh finished."), file=output)
                if queue.get("exit_code"):
                    print("Details: " + str(self.cache / "index.log"), file=sys.stderr)
                return queue.get("exit_code", 1)
            if deadline is not None and time.monotonic() >= deadline:
                print("Search refresh timed out; the background worker may still be running. " + self.repair(),
                      file=sys.stderr)
                return 1
            if not self.worker_active():
                # Re-read after observing the released lock to avoid an exit race.
                if read_json(self.cache / "queue.json").get("completed", 0) >= ticket:
                    continue
                print("Index worker stopped before completing. Run " + self.refresh_command + " --force; inspect " +
                      self.shown(self.cache / "index.log") + ".", file=sys.stderr)
                return 1
            time.sleep(0.05)

    def current_index(self, version):
        rendered = self.config()
        fingerprint, _ = snapshot(rendered, version)
        state = read_json(self.cache / "state.json")
        return (state.get("status") == "success" and
                (state.get("last_success") or {}).get("fingerprint") == fingerprint and
                (self.cache / "index.sqlite").is_file() and
                self.configuration_matches(rendered) and not self.worker_active())

    def lookup(self, args):
        self.prepare_models()
        tool, version = self.qmd_tool()
        retrieves = args[0] in {"search", "query", "vsearch", "get", "multi-get", "ls"}
        if retrieves and not self.current_index(version):
            timeout = float(self.setting("searchRefreshTimeout") or "60")
            if not math.isfinite(timeout) or timeout <= 0:
                raise ValueError(self.setting_name("searchRefreshTimeout") + " must be a positive number of seconds")
            print("Search index freshness is stale or unknown; refreshing before lookup.", file=sys.stderr)
            if self.wait_for(self.enqueue(), timeout=timeout, output=sys.stderr):
                raise RuntimeError("Search refresh failed; no results returned. " + self.repair())
            tool, version = self.qmd_tool()
            if not self.current_index(version):
                raise RuntimeError("Search freshness could not be established; no results returned. " + self.repair())
        with self.command_environment() as env:
            result = subprocess.run([tool, *args], cwd=self.root, env=env, text=True, stdout=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError("QMD lookup failed (exit " + str(result.returncode) + "); no results returned. " +
                               self.repair())
        if retrieves and not self.current_index(version):
            raise RuntimeError("Knowledge changed during lookup; results discarded. Retry after " +
                               self.refresh_command + " completes.")
        sys.stdout.write(result.stdout)
        return 0

    def diagnose_index(self):
        """Diagnose the search index alone, for a root that is not a set-up checkout; return the report."""
        report = {"root": str(self.root), "index": str(self.cache / "index.sqlite"),
                  "models": str((self.cache / "models").resolve()), "shared_models": str(shared_models()),
                  "worker_running": self.worker_active(), "python": sys.version.split()[0], "issues": [], "notices": []}
        try:
            rendered = self.config()
            report["collections"] = {k: v["path"] for k, v in rendered["collections"].items()}
            state = read_json(self.cache / "state.json")
            report["last_refresh"] = state or None
            models = self.cache / "models"
            if not models.is_dir() or models.resolve() != shared_models().resolve():
                report["issues"].append("Model cache must link to ~/.cache/qmd/models. Run " + self.prepare_command +
                                        " to repair " + self.shown(models) + ".")
            tool, version = self.qmd_tool()
            report.update(qmd=tool, qmd_version=version)
            fingerprint, report["document_counts"] = snapshot(rendered, version)
            last = state.get("last_success") or {}
            if not last:
                report["freshness"] = "unknown"
            elif (last.get("fingerprint") == fingerprint and (self.cache / "index.sqlite").is_file()
                  and self.configuration_matches(rendered)):
                report["freshness"] = "current"
            else:
                report["freshness"] = "stale"
            if report["freshness"] != "current" or state.get("status") == "failed":
                report["issues"].append("Search needs refresh or recovery. Run " + self.refresh_command +
                                        "; inspect " + self.shown(self.cache / "index.log") + " on failure.")
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            report["freshness"] = "unknown"
            report["issues"].append(str(error))
        return report

    def diagnose(self):
        """Diagnose the checkout's tools and hooks, then its search index; return the report."""
        report = {"root": str(self.root), "hooks_path": str(self.hooks_path()),
                  "hooks_mode": self.setting("hooks") or "bundled", "issues": [], "notices": []}
        report["direnv_available"] = bool(shutil.which("direnv"))
        report["git_version"] = git("--version", root=self.root)
        report["primary_checkout"] = str(primary_checkout(self.root))
        for command, argument in (("direnv", "version"), ("shellcheck", "--version")):
            report[command + "_version"] = None
            if shutil.which(command):
                result = subprocess.run([command, argument], cwd=self.root, text=True, capture_output=True, timeout=15)
                report[command + "_version"] = result.stdout.strip()
                if result.returncode:
                    report["issues"].append(command + " is installed but its version check failed.")
        if not report["direnv_available"] and (self.root / ".envrc").exists():
            report["issues"].append(DIRENV_MISSING)
        if not shutil.which("shellcheck"):
            report["issues"].append(SHELLCHECK_MISSING)
        active = self.hooks_path()
        if report["hooks_mode"] == "bundled":
            if self.shared_hooks(active):
                error = self.shared_hooks_error(active)
                if error:
                    report["issues"].append(error)
            elif (active.resolve() != (self.root / "bin/hooks").resolve() or
                  any(not os.access(active / e, os.X_OK) for e in EVENTS)):
                report["issues"].append("Bundled hooks are not active. Run bin/setup.")
        elif report["hooks_mode"] == "external":
            observations = read_json(self.cache / "hooks.json")
            report["observed_hooks"] = observations
            missing = [e for e in EVENTS if observations.get(e, {}).get("path") != str(active)]
            if missing:
                report["issues"].append("External forwarding not yet observed for: " + ", ".join(missing) + ". Follow docs/foundation/knowledge-search.md#existing-hooks.")
            report["notices"].append("Hook observations record past runs; re-verify after changing a hook manager.")
        else:
            report["issues"].append("Invalid knowledge.hooks setting.")
        index = self.diagnose_index()
        for key in ("issues", "notices"):
            index[key] = report[key] + index[key]
        return dict(report, **index)


def config():
    """Render this checkout's collections for the memory audit; return them with an empty list.

    The audit runs this from a clone of origin's default branch, which can hold another release than the audit
    itself, so it keeps the (collections, warnings) shape that every release's audit reads."""
    return Knowledge().config(), []


def cli(action):
    args = sys.argv[1:]
    engine = Knowledge()
    try:
        if Path(git("rev-parse", "--show-toplevel")).resolve() != engine.root:
            raise ValueError("Copy the starter into the target checkout root before running its tools")
        if action == "prep":
            if len(args) > 1:
                raise ValueError("Usage: bin/prep-worktree [checkout-root]")
            root = Path(args[0]).resolve() if args else engine.root
            prepare(root)
            return setup_application(root)
        if action == "setup":
            if args:
                raise ValueError("Usage: bin/setup")
            engine.config()  # Validate before changing local setup.
            engine.install_hooks()
            alias = '!f() { "$(git rev-parse --show-toplevel)/bin/knowledge" "$@"; }; f'
            existing_alias = git("config", "--get", "alias.knowledge", optional=True)
            if not existing_alias:
                git("config", "--local", "alias.knowledge", alias)
            elif existing_alias != alias:
                print("Preserved existing git knowledge alias; use bin/knowledge directly.")
            prepare(engine.root)
            code = engine.wait_for(engine.enqueue())
            # Project-owned dependency setup runs only after the foundation is ready.
            return code or setup_application(engine.root)
        if action == "index":
            if len(args) == 2 and args[0] == "--worker":
                return engine.worker(int(args[1]))
            if any(a not in {"--background", "--force"} for a in args):
                raise ValueError("Usage: bin/qmd-index [--background] [--force]")
            ticket = engine.enqueue(force="--force" in args)
            return 0 if "--background" in args else engine.wait_for(ticket)
        if action == "doctor":
            if args not in ([], ["--json"]):
                raise ValueError("Usage: bin/doctor [--json]")
            report = engine.diagnose()
            if args:
                print(json.dumps(report, indent=2))
            else:
                for key in ("root", "primary_checkout", "hooks_mode", "hooks_path", "git_version", "python", "qmd_version", "direnv_version", "shellcheck_version", "index", "models", "shared_models", "worker_running", "freshness", "collections", "last_refresh"):
                    print(key + ": " + str(report.get(key)))
                for message in report["notices"] + report["issues"]:
                    print(message)
            return bool(report["issues"])
        if action == "hook":
            if not args or args[0] not in EVENTS:
                raise ValueError("Usage: bin/knowledge-hook <" + "|".join(EVENTS) + "> [hook arguments]")
            event = args[0]
            with lock_file(engine.cache / "hooks.lock"):
                observed = read_json(engine.cache / "hooks.json")
                observed[event] = {"at": stamp(), "path": str(engine.hooks_path())}
                atomic_json(engine.cache / "hooks.json", observed)
            if event == "pre-push":
                updates = sys.stdin.read()
                return engine.check_push(updates) or engine.pre_push_application(args[1:], updates)
            new_checkout = event == "post-checkout" and len(args) >= 4 and args[3] == "1" and args[1] and set(args[1]) == {"0"}
            if new_checkout:
                prepare(engine.root)
            engine.enqueue()
            if new_checkout:
                # A new worktree gets the project's dependencies, such as its .venv, as bin/setup gives a fresh
                # clone; a failure is reported but leaves Git a usable checkout.
                setup_application(engine.root)
            return 0
        if action == "knowledge":
            allowed = {"search", "query", "vsearch", "get", "multi-get", "ls", "status", "--version"}
            if not args or (args[0] not in allowed and args != ["context", "list"]):
                raise ValueError("Usage: bin/knowledge <search|query|vsearch|get|multi-get|ls|status> [arguments]. Edit .config/knowledge.json for collections; use bin/qmd-index for refreshes.")
            if "--index" in args or any(a.startswith("--index=") for a in args):
                raise ValueError("This command uses the checkout's own index; named indexes are not supported")
            return engine.lookup(args)
        raise ValueError("Unknown command")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        if action == "knowledge":
            print("Handle this failure as ~/AGENTS.md says for a failed knowledge search. To repair, run bin/doctor and read .cache/qmd/index.log, as docs/foundation/knowledge-search.md#search-failures describes.", file=sys.stderr)
        if action == "hook" and args[:1] == ["pre-push"]:
            # Fail closed: a push the hook could not check may carry broken pages.
            print("The pre-push hook could not finish, so Git refused the push. Run bin/doctor.", file=sys.stderr)
            return 1
        if action == "hook":
            print("Knowledge hook failed; Git can continue. Run bin/doctor.", file=sys.stderr)
            return 0
        return 1
