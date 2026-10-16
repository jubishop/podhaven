"""Local Claude audit orchestration.

Validated edits are committed to main and pushed; the user's checkout is never touched. A failure
shows a macOS notification and opens or updates one GitHub issue, which the next success closes.
"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

from _checks import validate
from _knowledge import atomic_json
from _memory_index import update as update_index

ROOT = Path(__file__).resolve().parents[1]
LABEL = "com.jubishop.podhaven.memory-audit"
MODEL = "claude-haiku-5-5"
REPOSITORY = "jubishop/podhaven"
FAILURE_ISSUE = "Memory audit failing"
RETENTION_DAYS = 60


def command(args, cwd, env, timeout=120, input=None):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout, input=input)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {(result.stderr or result.stdout).strip()}")
    return result.stdout


def environment():
    return {key: os.environ[key] for key in
            ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "CLAUDE_CONFIG_DIR")
            if key in os.environ}


def output_schema():
    def record(properties):
        return {"type": "object", "properties": properties,
                "required": list(properties), "additionalProperties": False}

    string = {"type": "string"}
    return record({
        "report": string,
        "findings": {"type": "array", "items": record({
            "path": string, "verdict": {"type": "string", "enum": ["keep", "archive"]}, "evidence": string,
        })},
        "changes": {"type": "array", "items": record({
            "path": string, "archive": {"type": "boolean"}, "content": string,
        })},
    })


def apply_result(repo, result, notes):
    findings = result["findings"]
    if (len(findings) != len(notes) or {item["path"] for item in findings} != set(notes)
            or any(item["verdict"] not in ("keep", "archive") or not item["evidence"].strip()
                   for item in findings)):
        raise ValueError("The result must cover every active note exactly once with a verdict and evidence")
    report = result["report"]
    reviewed = re.search(r"(?m)^- Active notes reviewed: (\d+)\s*$", report)
    if (not report.startswith("# Memory audit report\n") or "\n## Per-note findings\n" not in report
            or not reviewed or int(reviewed[1]) != len(notes)):
        raise ValueError("The report is missing its required sections or reviewed count")
    verdicts = {item["path"]: item["verdict"] for item in findings}
    planned = []
    seen = set()
    for item in result["changes"]:
        path = item["path"]
        if path not in notes or path in seen:
            raise ValueError("Changes must name each existing active note at most once: " + path)
        seen.add(path)
        if not isinstance(item["archive"], bool) or not isinstance(item["content"], str) or not item["content"].strip():
            raise ValueError("Changes need an archive boolean and complete nonempty content")
        if item["archive"] != (verdicts[path] == "archive"):
            raise ValueError("Change and finding disagree about archival: " + path)
        source = repo / path
        destination = repo / "memory/archive" / source.name if item["archive"] else source
        if item["archive"] and (destination.exists() or destination.is_symlink()):
            raise ValueError("Cannot overwrite an existing archive: " + str(destination))
        if source.is_symlink() or not source.is_file() or destination.parent.is_symlink():
            raise ValueError("Memory paths must be regular files in real directories")
        planned.append((source, destination, item["content"]))
    if any(verdict == "archive" and path not in seen for path, verdict in verdicts.items()):
        raise ValueError("Every archive verdict requires an archival change")
    originals = {source: source.read_bytes() for source, _, _ in planned}
    readme = repo / "memory/README.md"
    originals[readme] = readme.read_bytes()
    try:
        for source, destination, content in planned:
            destination.parent.mkdir(exist_ok=True)
            destination.write_text(content)
            if source != destination:
                source.unlink()
        errors = validate(repo, generated_memory_index=True)
        if errors:
            raise ValueError("\n".join(errors))
        update_index(repo)
    except (OSError, ValueError):
        for source, destination, _ in planned:
            if source != destination:
                destination.unlink(missing_ok=True)
        for path, content in originals.items():
            path.write_bytes(content)
        raise


def verify_session(repo, run_dir, notes):
    """Reject a response unless the session read every active note and looked up evidence for each."""
    repo = repo.resolve()
    read, lookups = set(), 0
    for name in ("first-attempt-events.jsonl", "events.jsonl"):
        path = run_dir / name
        if not path.exists():
            continue
        for line in path.read_text(errors="replace").splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            message = event.get("message") if isinstance(event, dict) else None
            for block in (message.get("content") or []) if isinstance(message, dict) else []:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                arguments = block.get("input") if isinstance(block.get("input"), dict) else {}
                if block.get("name") == "Read":
                    target = Path(str(arguments.get("file_path", "")))
                    target = (target if target.is_absolute() else repo / target).resolve()
                    relative = target.relative_to(repo).as_posix() if target.is_relative_to(repo) else ""
                    if relative in notes:
                        read.add(relative)
                        continue
                if block.get("name") in ("Read", "Grep", "Glob", "Bash"):
                    lookups += 1
    unread = [note for note in notes if note not in read]
    if unread:
        raise ValueError("Read every active note in full with the Read tool before judging it; not read: "
                         + ", ".join(unread))
    if lookups < len(notes):
        raise ValueError(f"Check each note's claims against source or the captured evidence: {lookups} source or "
                         f"evidence lookups for {len(notes)} note{'s' if len(notes) != 1 else ''}")


def publish(root, repo, base, env, changes):
    """Commit the validated memory changes and push them to main; return the pushed commit."""
    name = command(["git", "config", "user.name"], root, env).strip()
    email = command(["git", "config", "user.email"], root, env).strip()
    git = ["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=" + name, "-c", "user.email=" + email]
    archived = sum(1 for change in changes if change["archive"])
    updated = len(changes) - archived
    command(git + ["add", "--all", "--", "memory"], repo, env)
    command(git + ["commit", "--quiet", "-m", "📝 docs(memory): Apply the weekly memory audit", "-m",
                   f"The audit of {base[:8]} archived {archived} and updated {updated} notes. It read every "
                   "active note, and its proposal passed the memory checks."], repo, env)
    command(["git", "remote", "add", "origin", command(["git", "remote", "get-url", "origin"], root, env).strip()],
            repo, env)
    for url in command(["git", "remote", "get-url", "--push", "--all", "origin"], root, env).splitlines():
        command(["git", "remote", "set-url", "--add", "--push", "origin", url], repo, env)
    command(["git", "fetch", "--quiet", "origin", "main"], repo, env)
    latest = command(["git", "rev-parse", "FETCH_HEAD"], repo, env).strip()
    if latest != base:
        moved = subprocess.run(["git", "diff", "--quiet", base, latest, "--", "memory"], cwd=repo, env=env,
                               capture_output=True, text=True)
        if moved.returncode == 1:
            raise RuntimeError("main changed memory/ during the audit; the next run audits the new notes")
        if moved.returncode:
            raise RuntimeError("git diff failed (" + str(moved.returncode) + "): " + moved.stderr.strip())
        command(git + ["rebase", "--quiet", latest], repo, env)
    command(["git", "-c", "core.hooksPath=/dev/null", "push", "--quiet", "origin", "HEAD:refs/heads/main"],
            repo, env, timeout=300)
    return command(["git", "rev-parse", "HEAD"], repo, env).strip()


def failure_issue(root, env):
    issues = json.loads(command(["gh", "issue", "list", "--repo", REPOSITORY, "--state", "open", "--search",
                                 f'in:title "{FAILURE_ISSUE}"', "--json", "number,title"], root, env))
    return next((item["number"] for item in issues if item.get("title") == FAILURE_ISSUE), None)


def report_failure(root, env, meta):
    """Notify on this Mac and open or update the failure issue; never raise."""
    error = str(meta.get("error") or "Unknown error").replace(str(Path.home()), "~")
    run_name = Path(meta["directory"]).name
    try:
        subprocess.run(["osascript", "-e", "on run argv", "-e",
                        "display notification (item 1 of argv) with title (item 2 of argv)", "-e", "end run",
                        error.splitlines()[0][:200], "PodHaven memory audit failed"],
                       env=env, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as problem:
        print("Could not show the failure notification: " + str(problem), file=sys.stderr, flush=True)
    body = (f"The weekly memory audit failed in run `{run_name}` at {meta.get('finishedAt')}.\n\n"
            f"```\n{error[:3000]}\n```\n\nInspect `.cache/memory-audit/runs/{run_name}/` and "
            "`.cache/memory-audit/latest.json` in the primary checkout on the Mac, fix the cause, and run "
            "`bin/memory-audit run`. The next successful run closes this issue.\n")
    try:
        number = failure_issue(root, env)
        if number:
            command(["gh", "issue", "comment", str(number), "--repo", REPOSITORY, "--body-file", "-"],
                    root, env, input=body)
        else:
            command(["gh", "issue", "create", "--repo", REPOSITORY, "--title", FAILURE_ISSUE, "--body-file", "-"],
                    root, env, input=body)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as problem:
        print("Could not open or update the failure issue: " + str(problem), file=sys.stderr, flush=True)


def close_failure_issue(root, env, run_name):
    try:
        number = failure_issue(root, env)
        if number:
            command(["gh", "issue", "close", str(number), "--repo", REPOSITORY, "--comment",
                     f"Run `{run_name}` succeeded."], root, env)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as problem:
        print("Could not close the failure issue: " + str(problem), file=sys.stderr, flush=True)


def prune_runs(state, keep):
    cutoff = time.time() - RETENTION_DAYS * 86400
    for directory in (state / "runs").glob("*"):
        if directory.is_dir() and not directory.is_symlink() and str(directory) not in keep \
                and directory.stat().st_mtime < cutoff:
            shutil.rmtree(directory)


def run_model(repo, run_dir, env, prompt, timeout=5400):
    # Restricted mode ignores user and project settings. Without edit tools or edit rules, any write,
    # network command, or read outside the clone needs approval, which --permission-prompts none denies.
    permissions = {"allow": ["Bash(jq *)", "Bash(qmd search *)"]}
    args = ["claude", "-p", "--restricted", "--no-session-persistence", "--strict-mcp-config",
            "--model", MODEL, "--effort", "high", "--tools", "Bash,Read,Glob,Grep",
            "--permission-mode", "default", "--permission-prompts", "none",
            "--settings", json.dumps({"permissions": permissions}),
            "--output-format", "stream-json", "--verbose", "--json-schema", json.dumps(output_schema())]
    with (run_dir / "events.jsonl").open("w") as events, (run_dir / "claude.log").open("w") as log:
        process = subprocess.Popen(args, cwd=repo, env=env, text=True, stdin=subprocess.PIPE,
                                   stdout=events, stderr=log, start_new_session=True)
        try:
            process.communicate(prompt, timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise RuntimeError("Claude exceeded the 90-minute limit; see " + str(log.name)) from None
        if process.returncode:
            raise RuntimeError(f"Claude exited {process.returncode}; see {log.name}")
    result = None
    for line in (run_dir / "events.jsonl").read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") == "result":
            result = event.get("structured_output")
    if not isinstance(result, dict):
        raise RuntimeError("Claude returned no structured result; see " + str(run_dir / "events.jsonl"))
    atomic_json(run_dir / "result.json", result)


def run(root=ROOT, force=False):
    root = root.resolve()
    state = root / ".cache/memory-audit"
    state.mkdir(parents=True, exist_ok=True)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"status": "skipped", "reason": "Another local audit is running"}
        runs = state / "runs"
        runs.mkdir(exist_ok=True)
        previous_path = state / "last-success.json"
        previous = json.loads(previous_path.read_text()) if previous_path.exists() else None
        last = json.loads((state / "latest.json").read_text()) if (state / "latest.json").exists() else {}
        prune_runs(state, {item.get("directory") for item in (previous or {}, last)})
        prefix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
        run_dir = Path(tempfile.mkdtemp(prefix=prefix, dir=runs))
        meta = {"status": "running", "directory": str(run_dir), "model": MODEL, "provider": "claude.ai"}
        atomic_json(state / "latest.json", meta)
        env = environment()
        try:
            command(["git", "fetch", "--quiet", "origin", "main"], root, env)
            base = command(["git", "rev-parse", "FETCH_HEAD"], root, env).strip()
            meta["baseSha"] = base
            context = {"baseSha": base}
            for kind, key, extra in (("issue", "issues", "labels"), ("pr", "pullRequests", "mergedAt,headRefName")):
                fields = "number,title,state,closedAt,updatedAt,url,body," + extra
                context[key] = json.loads(command([
                    "gh", kind, "list", "--repo", REPOSITORY, "--state", "all", "--limit", "1000", "--json", fields,
                ], root, env))
            prompt = (ROOT / "bin/memory-audit-prompt.md").read_text()
            fingerprint = hashlib.sha256(json.dumps(context, sort_keys=True).encode() + prompt.encode()
                                         + Path(__file__).read_bytes()).hexdigest()
            # A run after a failure or crash always audits, so the failure issue can close.
            if not force and previous and previous["inputHash"] == fingerprint \
                    and last.get("status") in ("success", "skipped"):
                meta.update(status="skipped", reason="No repository, issue, PR, or audit instruction changes",
                            previousDirectory=previous["directory"])
                return meta
            login = subprocess.run(["claude", "auth", "status", "--json"], cwd=root, env=env,
                                   capture_output=True, text=True, timeout=30)
            try:
                status = json.loads(login.stdout) if not login.returncode else {}
            except ValueError:
                status = {}
            if not (status.get("loggedIn") and status.get("authMethod") == "claude.ai"
                    and status.get("apiProvider") == "firstParty"):
                raise RuntimeError("Memory audit requires a saved Claude subscription login; run claude auth login. "
                                   "API billing is disabled.")
            repo = run_dir / "repository"
            command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--quiet", "--shared", "--no-checkout",
                     str(root), str(repo)], root, env)
            command(["git", "-c", "core.hooksPath=/dev/null", "checkout", "--quiet", "--detach", base], repo, env)
            command(["git", "remote", "remove", "origin"], repo, env)
            since = (previous or {}).get("completedAt") or \
                (datetime.now(timezone.utc) - timedelta(days=7)).isoformat(timespec="seconds")
            commits = command(["git", "log", "--since=" + since, "--no-merges", "--date=short",
                               "--format=%h %ad %s", base], repo, env).splitlines()
            notes = sorted(path.relative_to(repo).as_posix() for path in (repo / "memory").glob("*.md")
                           if path.name != "README.md")
            if (repo / "memory").is_symlink() or any((repo / path).is_symlink() for path in notes):
                raise ValueError("Active memory notes must not be symbolic links")
            context.update(activeNoteCount=len(notes), activeNotes=notes, lastSuccessfulAudit=previous,
                           runDateUtc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                           commitsSinceLastAudit=commits)
            artifacts = repo / "artifacts"
            artifacts.mkdir(exist_ok=True)
            atomic_json(artifacts / "memory-audit-context.json", context)
            atomic_json(run_dir / "memory-audit-context.json", context)
            qmd_dir = repo / ".cache/memory-audit-qmd"
            config_dir = qmd_dir / "config"
            config_dir.mkdir(parents=True)
            env.update(QMD_CONFIG_DIR=str(config_dir), XDG_CACHE_HOME=str(qmd_dir / "cache"))
            config = command([sys.executable, "-B", "bin/knowledge-config", "--ci"], repo, env)
            (config_dir / "index.yml").write_text(config)
            command(["qmd", "update"], repo, env, timeout=300)
            deadline = time.monotonic() + 5400
            for attempt in range(2):
                run_model(repo, run_dir, env, prompt, timeout=max(1, deadline - time.monotonic()))
                if (command(["git", "rev-parse", "HEAD"], repo, env).strip() != base
                        or command(["git", "status", "--porcelain", "--untracked-files=all"], repo, env).strip()):
                    raise ValueError("The read-only audit changed its checkout")
                result = json.loads((run_dir / "result.json").read_text())
                try:
                    verify_session(repo, run_dir, notes)
                    apply_result(repo, result, notes)
                    break
                except ValueError as error:
                    if attempt:
                        raise
                    (run_dir / "validation-error.txt").write_text(str(error) + "\n")
                    for name, saved in (("result.json", "rejected-result.json"),
                                        ("events.jsonl", "first-attempt-events.jsonl"),
                                        ("claude.log", "first-attempt-claude.log")):
                        (run_dir / name).rename(run_dir / saved)
                    prompt += ("\n\nYour previous response failed validation. The runner restored the original notes. "
                               "Repair this response using the findings you already gathered; do not repeat work you "
                               "already did. If the error says notes were not read or claims were not checked, do that "
                               "work now; the runner counts both attempts. "
                               "If an archive breaks links in an existing archive, ledger, or doc, keep that active note "
                               "because those referring files are outside your edit scope. Update findings, report counts, "
                               "and proposed contents together. Return the complete corrected JSON.\n\nValidation error:\n"
                               + str(error) + "\n\nPrevious response:\n" + json.dumps(result))
            command(["git", "add", "--intent-to-add", "--", "memory"], repo, env)
            command(["git", "diff", "--check"], repo, env)
            patch = command(["git", "diff", "--binary", "HEAD", "--", "memory"], repo, env)
            (run_dir / "memory-audit.patch").write_text(patch)
            (run_dir / "memory-audit-report.md").write_text(result["report"])
            changed = command(["git", "diff", "--name-only", "HEAD"], repo, env).splitlines()
            if changed:
                meta["publishedCommit"] = publish(root, repo, base, env, result["changes"])
            meta.update(status="success", inputHash=fingerprint, activeNoteCount=len(notes), changedFiles=changed,
                        completedAt=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            atomic_json(previous_path, meta)
            close_failure_issue(root, env, run_dir.name)
            return meta
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            meta.update(status="failed", error=str(error),
                        finishedAt=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            report_failure(root, env, meta)
            raise
        finally:
            # The run folder keeps the context, report, patch, and logs; the clone is only working space.
            shutil.rmtree(run_dir / "repository", ignore_errors=True)
            meta["finishedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
            atomic_json(run_dir / "run-meta.json", meta)
            atomic_json(state / "latest.json", meta)


def install(root=ROOT):
    if sys.platform != "darwin":
        raise RuntimeError("The launchd schedule requires macOS")
    root = root.resolve()
    python = Path.home() / ".local/bin/python3"
    if not os.access(python, os.X_OK):
        raise RuntimeError(f"Missing the default Python {python}; run `uv python install --default`")
    tool_paths = [str(python.parent)]
    for executable in ("claude", "qmd", "gh", "git", "rg", "node", "bun"):
        path = shutil.which(executable)
        if not path:
            if executable in ("node", "bun"):
                continue
            raise RuntimeError("Missing required command: " + executable)
        directory = Path(path).parent.resolve()
        fnm = (Path.home() / ".local/share/fnm").resolve()
        if directory.is_relative_to(fnm / "node-versions"):
            # fnm's default alias follows each Node update; a version folder would go stale.
            directory = Path.home() / ".local/share/fnm/aliases/default/bin"
        tool_paths.append(str(directory))
    tool_paths.extend(("/usr/bin", "/bin", "/usr/sbin", "/sbin"))
    agents = Path.home() / "Library/LaunchAgents"
    agents.mkdir(parents=True, exist_ok=True)
    log_dir = root / ".cache/memory-audit"
    log_dir.mkdir(parents=True, exist_ok=True)
    plist = agents / (LABEL + ".plist")
    settings = {
        "Label": LABEL,
        "ProgramArguments": [str(python), "-B", str(root / "bin/memory-audit"), "run"],
        "WorkingDirectory": str(root),
        "EnvironmentVariables": {"PATH": os.pathsep.join(dict.fromkeys(tool_paths))},
        "StartCalendarInterval": {"Weekday": 6, "Hour": 6, "Minute": 0},
        "ProcessType": "Background",
        "StandardOutPath": str(log_dir / "launchd.log"),
        "StandardErrorPath": str(log_dir / "launchd-error.log"),
    }
    scheduled_env = environment() | settings["EnvironmentVariables"]
    command(["qmd", "--version"], root, scheduled_env)
    domain = f"gui/{os.getuid()}"
    loaded = subprocess.run(["launchctl", "print", domain + "/" + LABEL], capture_output=True)
    if loaded.returncode == 0:
        if re.search(rb"\bpid = \d+", loaded.stdout):
            raise RuntimeError("The scheduled audit is running; reinstall after it finishes")
        command(["launchctl", "bootout", domain + "/" + LABEL], root, environment())
    plist.write_bytes(plistlib.dumps(settings))
    command(["plutil", "-lint", str(plist)], root, environment())
    command(["launchctl", "bootstrap", domain, str(plist)], root, environment())
    command(["launchctl", "enable", domain + "/" + LABEL], root, environment())
    return {"status": "installed", "plist": str(plist), "schedule": "Saturday 06:00, Mac local time"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "install"))
    parser.add_argument("--force", action="store_true", help="Audit even when inputs match the last successful run")
    args = parser.parse_args()
    try:
        result = install() if args.action == "install" else run(force=args.force)
        print(json.dumps(result, indent=2), flush=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr, flush=True)
        return 1
