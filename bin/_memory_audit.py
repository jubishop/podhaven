"""Local Luna audit orchestration; proposed edits never reach the user's checkout."""

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
from datetime import datetime, timezone

from _checks import validate
from _knowledge import atomic_json
from _memory_index import update as update_index

ROOT = Path(__file__).resolve().parents[1]
LABEL = "com.jubishop.podhaven.memory-audit"
MODEL = "gpt-6-luna"
REPOSITORY = "jubishop/podhaven"


def command(args, cwd, env, timeout=120):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {(result.stderr or result.stdout).strip()}")
    return result.stdout


def environment():
    return {key: os.environ[key] for key in
            ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "CODEX_HOME")
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


def run_model(repo, run_dir, env, prompt, timeout=5400):
    schema = run_dir / "output-schema.json"
    atomic_json(schema, output_schema())
    args = ["codex", "--no-daemon", "-a", "never", "exec", "--ignore-user-config", "--ignore-rules",
            "--ephemeral", "--model", MODEL, "--sandbox", "read-only",
            "-c", 'model_provider="openai"', "-c", 'forced_login_method="chatgpt"',
            "-c", 'model_reasoning_effort="high"', "-c", "agents.enabled=false",
            "-c", "allow_login_shell=false", "-c", 'shell_environment_policy.inherit="all"',
            "-c", "shell_environment_policy.ignore_default_excludes=false",
            "-c", 'web_search="disabled"', "--color", "never", "--json",
            "--output-schema", str(schema), "--output-last-message", str(run_dir / "result.json"), "-"]
    with (run_dir / "events.jsonl").open("w") as events, (run_dir / "codex.log").open("w") as log:
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
            raise RuntimeError("Luna exceeded the 90-minute limit; see " + str(log.name)) from None
        if process.returncode:
            raise RuntimeError(f"Luna exited {process.returncode}; see {log.name}")


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
        prefix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
        run_dir = Path(tempfile.mkdtemp(prefix=prefix, dir=runs))
        meta = {"status": "running", "directory": str(run_dir), "model": MODEL, "provider": "chatgpt"}
        atomic_json(state / "latest.json", meta)
        try:
            env = environment()
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
            previous_path = state / "last-success.json"
            previous = json.loads(previous_path.read_text()) if previous_path.exists() else None
            if not force and previous and previous["inputHash"] == fingerprint:
                meta.update(status="skipped", reason="No repository, issue, PR, or audit instruction changes",
                            previousDirectory=previous["directory"])
                return meta
            login = subprocess.run(["codex", "login", "status"], cwd=root, env=env,
                                   capture_output=True, text=True, timeout=30)
            if login.returncode or "Logged in using ChatGPT" not in login.stdout + login.stderr:
                raise RuntimeError("Memory audit requires saved ChatGPT login; run codex login. API billing is disabled.")
            repo = run_dir / "repository"
            command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--quiet", "--shared", "--no-checkout",
                     str(root), str(repo)], root, env)
            command(["git", "-c", "core.hooksPath=/dev/null", "checkout", "--quiet", "--detach", base], repo, env)
            command(["git", "remote", "remove", "origin"], repo, env)
            notes = sorted(path.relative_to(repo).as_posix() for path in (repo / "memory").glob("*.md")
                           if path.name != "README.md")
            if (repo / "memory").is_symlink() or any((repo / path).is_symlink() for path in notes):
                raise ValueError("Active memory notes must not be symbolic links")
            context.update(activeNoteCount=len(notes), activeNotes=notes, lastSuccessfulAudit=previous,
                           runDateUtc=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            artifacts = repo / "artifacts"
            artifacts.mkdir(exist_ok=True)
            atomic_json(artifacts / "memory-audit-context.json", context)
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
                    apply_result(repo, result, notes)
                    break
                except ValueError as error:
                    if attempt:
                        raise
                    (run_dir / "validation-error.txt").write_text(str(error) + "\n")
                    for name, saved in (("result.json", "rejected-result.json"),
                                        ("events.jsonl", "first-attempt-events.jsonl"),
                                        ("codex.log", "first-attempt-codex.log")):
                        (run_dir / name).rename(run_dir / saved)
                    prompt += ("\n\nYour previous response failed validation. The runner restored the original notes. "
                               "Repair this response using the findings you already gathered; do not repeat the whole audit. "
                               "If an archive breaks links in an existing archive, ledger, or doc, keep that active note "
                               "because those referring files are outside your edit scope. Update findings, report counts, "
                               "and proposed contents together. Return the complete corrected JSON.\n\nValidation error:\n"
                               + str(error) + "\n\nPrevious response:\n" + json.dumps(result))
            command(["git", "add", "--intent-to-add", "--", "memory"], repo, env)
            command(["git", "diff", "--check"], repo, env)
            patch = command(["git", "diff", "--binary", "HEAD", "--", "memory"], repo, env)
            (run_dir / "memory-audit.patch").write_text(patch)
            (run_dir / "memory-audit-report.md").write_text(result["report"])
            meta.update(status="success", inputHash=fingerprint, activeNoteCount=len(notes),
                        changedFiles=command(["git", "diff", "--name-only", "HEAD"], repo, env).splitlines(),
                        completedAt=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            atomic_json(previous_path, meta)
            return meta
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            meta.update(status="failed", error=str(error))
            raise
        finally:
            meta["finishedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
            atomic_json(run_dir / "run-meta.json", meta)
            atomic_json(state / "latest.json", meta)


def install(root=ROOT):
    if sys.platform != "darwin":
        raise RuntimeError("The launchd schedule requires macOS")
    root = root.resolve()
    tool_paths = [str(Path(sys.executable).parent)]
    for executable in ("codex", "qmd", "gh", "git", "rg", "node", "bun"):
        path = shutil.which(executable)
        if not path:
            if executable in ("node", "bun"):
                continue
            raise RuntimeError("Missing required command: " + executable)
        tool_paths.append(str(Path(path).parent.resolve()))
    tool_paths.extend(("/usr/bin", "/bin", "/usr/sbin", "/sbin"))
    agents = Path.home() / "Library/LaunchAgents"
    agents.mkdir(parents=True, exist_ok=True)
    log_dir = root / ".cache/memory-audit"
    log_dir.mkdir(parents=True, exist_ok=True)
    plist = agents / (LABEL + ".plist")
    settings = {
        "Label": LABEL,
        "ProgramArguments": [sys.executable, "-B", str(root / "bin/memory-audit"), "run"],
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
