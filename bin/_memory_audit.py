"""Run, schedule, or show the settings of the weekly Claude audit of this project's memory notes.

Validated edits are committed to main and pushed; the user's checkout is never touched. A failure
shows a macOS notification and opens or updates one GitHub issue, which the next success closes.
Project Starter manages this file; see docs/foundation/memory-audit.md.
"""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone

from _checks import link_targets, local_target, validate
from _knowledge import atomic_json

ROOT = Path(__file__).resolve().parents[1]
MODEL = "claude-sonnet-5-5"
# The project's own Anthropic API key. Only this line of the checkout's ignored .env is read.
API_KEY = "MEMORY_AUDIT_ANTHROPIC_API_KEY"
API_KEY_LINE = re.compile(r"\s*(?:export\s+)?" + API_KEY + r"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s#]*))\s*(?:#.*)?")
# Refusals of the key that the subscription reruns. Claude Code shortens the API's "Your credit balance is
# too low to access the Anthropic API" to "Credit balance is too low"; a spend limit reads "You have reached
# your specified API usage limits"; a rejected key is HTTP 401 or 403.
# Each is (trigger, message pattern, Claude Code error category, HTTP statuses).
KEY_REFUSALS = (
    ("credit-balance", re.compile(r"credit balance (?:is )?too low", re.IGNORECASE), "billing_error", ()),
    ("usage-limit", re.compile(r"usage limits", re.IGNORECASE), None, ()),
    ("key-rejected", None, "authentication_failed", (401, 403)),
)
FAILURE_ISSUE = "Memory audit failing"
# The tool boundary check's bogus key, which only its local stand-in API receives.
BOUNDARY_KEY = "sk-ant-api03-memory-audit-boundary-check"
RETENTION_DAYS = 60
WEEKDAYS = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
SETTINGS = ("repository", "launchAgentLabel", "schedule", "issueLabels", "commitTrailers", "indexHeading", "context",
            "lockWaitMinutes")
# Every project's audit on this machine computes the same path, so their runs take turns.
TURN_LOCK = Path(".cache/project-starter/memory-audit.lock")
GITHUB_URL = r"(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(?:\.git)?/?"
# Renders the clone's shared search collections with its own Project Starter loader. A fresh clone has
# no local Git settings, so the personal home-memory collection is never added.
INDEX_CONFIG = ("import json, sys; sys.path.insert(0, sys.argv[1]); from _knowledge import config; "
                "print(json.dumps(config()[0], indent=2, sort_keys=True))")


def command(args, cwd, env, timeout=120, input=None):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout, input=input)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {(result.stderr or result.stdout).strip()}")
    return result.stdout


def environment():
    # API keys stay out; only the API-key attempt adds the project's own key.
    return {key: os.environ[key] for key in
            ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "TMPDIR", "CLAUDE_CONFIG_DIR")
            if key in os.environ}


def settings(root, env):
    """Return the memoryAudit settings from .config/knowledge.json, validated and with defaults."""
    raw = json.loads((root / ".config/knowledge.json").read_text()).get("memoryAudit", {})

    def invalid(message):
        return ValueError("memoryAudit in .config/knowledge.json: " + message)

    def one_line(value):
        return isinstance(value, str) and value.strip() == value and value and "\n" not in value

    if not isinstance(raw, dict):
        raise invalid("must be an object")
    unknown = sorted(set(raw) - set(SETTINGS))
    if unknown:
        raise invalid("unsupported " + ", ".join(unknown) + "; the settings are " + ", ".join(SETTINGS))
    repository = raw.get("repository")
    if repository is None:
        origin = subprocess.run(["git", "remote", "get-url", "origin"], cwd=root, env=env, capture_output=True, text=True)
        match = re.fullmatch(GITHUB_URL, origin.stdout.strip()) if not origin.returncode else None
        if not match:
            raise ValueError("The memory audit reports to GitHub, but origin is " + (origin.stdout.strip() or "missing")
                             + "; set memoryAudit.repository to OWNER/NAME in .config/knowledge.json")
        repository = match[1] + "/" + match[2]
    elif not isinstance(repository, str) or not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+", repository):
        raise invalid("repository must be a GitHub OWNER/NAME")
    owner, name = repository.split("/")
    label = raw.get("launchAgentLabel", f"com.{owner}.{name}.memory-audit".lower())
    if not isinstance(label, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", label):
        raise invalid("launchAgentLabel must be letters, digits, dots, hyphens, and underscores, such as "
                      "com.owner.project.memory-audit")
    schedule = raw.get("schedule", {})
    if not isinstance(schedule, dict) or set(schedule) - {"weekday", "hour", "minute"}:
        raise invalid("schedule must be an object with only weekday, hour, and minute")
    schedule = {"weekday": "Saturday", "hour": 6, "minute": 0} | schedule
    if schedule["weekday"] not in WEEKDAYS:
        raise invalid("schedule.weekday must be one of " + ", ".join(WEEKDAYS))
    for key, limit in (("hour", 23), ("minute", 59)):
        value = schedule[key]
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= limit:
            raise invalid(f"schedule.{key} must be a whole number from 0 to {limit}")
    labels = raw.get("issueLabels", [])
    # The GitHub CLI splits a --label value at commas.
    if not isinstance(labels, list) or not all(one_line(item) and "," not in item for item in labels):
        raise invalid("issueLabels must be a list of existing GitHub label names without commas")
    trailers = raw.get("commitTrailers", {})
    if not isinstance(trailers, dict) or not all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", key) and one_line(value)
                                                 for key, value in trailers.items()):
        raise invalid('commitTrailers must map trailer names such as "Deploy" to one-line values')
    heading = raw.get("indexHeading", "Active pages")
    if not one_line(heading) or heading.startswith("#"):
        raise invalid("indexHeading must be the text of memory/README.md's level-two heading over its active notes")
    context = raw.get("context", "")
    if not isinstance(context, str):
        raise invalid("context must be a string")
    wait = raw.get("lockWaitMinutes", 180)
    if not isinstance(wait, int) or isinstance(wait, bool) or wait < 0:
        raise invalid("lockWaitMinutes must be a whole number of minutes, 0 or more")
    return {"repository": repository, "launchAgentLabel": label, "schedule": schedule, "issueLabels": labels,
            "commitTrailers": trailers, "indexHeading": heading, "context": context.strip(), "lockWaitMinutes": wait}


def api_key(root):
    """Return MEMORY_AUDIT_ANTHROPIC_API_KEY from the checkout's .env, or None when it is missing or empty."""
    path = root / ".env"
    if not path.is_file():
        return None
    key = None
    for line in path.read_text().splitlines():
        match = API_KEY_LINE.fullmatch(line)
        if match:
            key = next(value for value in match.groups() if value is not None)
    return key or None


def with_key(env, key):
    return env | {"ANTHROPIC_API_KEY": key} if key else env


def require_login(root, env, key):
    """Fail unless Claude Code will bill the first-party Anthropic API key given, or else the subscription."""
    login = subprocess.run(["claude", "auth", "status", "--json"], cwd=root, env=with_key(env, key),
                           capture_output=True, text=True, timeout=30)
    try:
        status = json.loads(login.stdout) if not login.returncode else {}
    except ValueError:
        status = {}
    if not (status.get("loggedIn") and status.get("apiProvider") == "firstParty"):
        status = {}
    if key and (status.get("authMethod"), status.get("apiKeySource")) != ("api_key", "ANTHROPIC_API_KEY"):
        raise RuntimeError(f"Claude Code would not bill the Anthropic API with {API_KEY} from .env; check "
                           "claude auth status --json with the key as ANTHROPIC_API_KEY")
    if not key and status.get("authMethod") != "claude.ai":
        raise RuntimeError("Memory audit requires a saved Claude subscription login; run claude auth login. Only "
                           f"{API_KEY} in .env may bill an API key instead.")


def key_refusal(run_dir):
    """Return how the API refused the audit's key, from Claude's stream-json events, or None for other failures.

    Only API failures count: the result event marked is_error and assistant events Claude Code synthesized
    from an API error, never the model's own text.
    """
    path = run_dir / "events.jsonl"
    failures = []
    for line in path.read_text(errors="replace").splitlines() if path.exists() else []:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "result" and event.get("is_error"):
            failures.insert(0, (event, str(event.get("result") or "")))
        elif event.get("type") == "assistant" and (event.get("is_api_error_message") or event.get("error")):
            message = event.get("message") if isinstance(event.get("message"), dict) else {}
            blocks = message.get("content") if isinstance(message.get("content"), list) else []
            failures.append((event, " ".join(str(block.get("text") or "") for block in blocks
                                             if isinstance(block, dict))))
    for event, text in failures:
        status, category = event.get("api_error_status"), event.get("error")
        for trigger, pattern, error, statuses in KEY_REFUSALS:
            if (pattern and pattern.search(text)) or (error and category == error) or status in statuses:
                return {"trigger": trigger, "status": status, "message": text.strip()[:500]}
    return None


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


def audit_prompt(options):
    prompt = (ROOT / "bin/memory-audit-prompt.md").read_text().replace("{{indexHeading}}", options["indexHeading"])
    context = "## Project context\n\n" + options["context"] + "\n\n" if options["context"] else ""
    return prompt.replace("{{projectContext}}\n\n", context)


def remove_index_entries(readme, archived, heading):
    """Drop the list entries that link to archived notes from the README's hand-maintained active index.

    Only the index section changes; any other README link to an archived note stays, so validation
    rejects that archive.
    """
    output, entry, inside = [], [], False

    def finish():
        try:
            targets = link_targets("".join(entry))
        except ValueError:
            targets = []
        if not any(local_target(readme, target)[0] in archived for target in targets):
            output.extend(entry)
        entry.clear()

    for line in readme.read_text().splitlines(keepends=True):
        if entry and line.strip() and line[0] in " \t":
            entry.append(line)
            continue
        if entry:
            finish()
        if line.startswith("#"):
            inside = line.rstrip() == "## " + heading
        if inside and re.match(r"[-*+] ", line):
            entry.append(line)
        else:
            output.append(line)
    if entry:
        finish()
    readme.write_text("".join(output).rstrip("\n") + "\n")


def apply_result(repo, result, notes, heading):
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
    archived = {source.resolve() for source, destination, _ in planned if source != destination}
    try:
        for source, destination, content in planned:
            destination.parent.mkdir(exist_ok=True)
            destination.write_text(content)
            if source != destination:
                source.unlink()
        if archived:
            remove_index_entries(readme, archived, heading)
        errors = validate(repo)
        if errors:
            raise ValueError("\n".join(errors))
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


def publish(root, repo, base, env, changes, options):
    """Commit the validated memory changes and push them to main on GitHub; return the pushed commit."""
    name = command(["git", "config", "user.name"], root, env).strip()
    email = command(["git", "config", "user.email"], root, env).strip()
    # Hooks stay off in the disposable clone; no hook gates a memory-only commit.
    git = ["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=" + name, "-c", "user.email=" + email]
    archived = sum(1 for change in changes if change["archive"])
    updated = len(changes) - archived
    message = ["-m", "📝 docs(memory): Apply the weekly memory audit", "-m",
               f"The audit of {base[:8]} archived {archived} and updated {updated} notes. It read every "
               "active note, and its proposal passed the memory checks."]
    if options["commitTrailers"]:
        message += ["-m", "\n".join(key + ": " + value for key, value in options["commitTrailers"].items())]
    command(git + ["add", "--all", "--", "memory"], repo, env)
    command(git + ["commit", "--quiet", *message], repo, env)
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


def failure_issue(root, env, repository):
    issues = json.loads(command(["gh", "issue", "list", "--repo", repository, "--state", "open", "--search",
                                 f'in:title "{FAILURE_ISSUE}"', "--json", "number,title"], root, env))
    return next((item["number"] for item in issues if item.get("title") == FAILURE_ISSUE), None)


def report_failure(root, env, meta, options):
    """Notify on this Mac and open or update the failure issue; never raise."""
    error = str(meta.get("error") or "Unknown error").replace(str(Path.home()), "~")
    run_name = Path(meta["directory"]).name
    project = options["repository"].split("/")[1] if options else root.name
    try:
        subprocess.run(["osascript", "-e", "on run argv", "-e",
                        "display notification (item 1 of argv) with title (item 2 of argv)", "-e", "end run",
                        error.splitlines()[0][:200], project + " memory audit failed"],
                       env=env, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as problem:
        print("Could not show the failure notification: " + str(problem), file=sys.stderr, flush=True)
    if not options:
        print("Could not open or update the failure issue without valid settings", file=sys.stderr, flush=True)
        return
    repository = options["repository"]
    body = (f"The weekly memory audit failed in run `{run_name}` at {meta.get('finishedAt')}.\n\n"
            f"```\n{error[:3000]}\n```\n\nInspect `.cache/memory-audit/runs/{run_name}/` and "
            "`.cache/memory-audit/latest.json` in the primary checkout on the Mac, fix the cause, and run "
            "`bin/memory-audit run`. The next successful run closes this issue.\n")
    try:
        number = failure_issue(root, env, repository)
        if number:
            command(["gh", "issue", "comment", str(number), "--repo", repository, "--body-file", "-"],
                    root, env, input=body)
            return
        create = ["gh", "issue", "create", "--repo", repository, "--title", FAILURE_ISSUE, "--body-file", "-"]
        labels = [argument for label in options["issueLabels"] for argument in ("--label", label)]
        try:
            command(create + labels, root, env, input=body)
        except RuntimeError as problem:
            if not labels:
                raise
            # An unlabeled issue still reports the failure.
            command(create, root, env, input=body + "\nThe runner could not apply the labels "
                    + ", ".join(options["issueLabels"]) + ": " + str(problem) + "\n")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as problem:
        print("Could not open or update the failure issue: " + str(problem), file=sys.stderr, flush=True)


def close_failure_issue(root, env, repository, run_name):
    try:
        number = failure_issue(root, env, repository)
        if number:
            command(["gh", "issue", "close", str(number), "--repo", repository, "--comment",
                     f"Run `{run_name}` succeeded."], root, env)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as problem:
        print("Could not close the failure issue: " + str(problem), file=sys.stderr, flush=True)


def take_turn(minutes, state, meta):
    """Wait for this machine's audit lock, which other projects' audits share; return its open file."""
    path = Path.home() / TURN_LOCK
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.open("a")
    deadline = time.monotonic() + minutes * 60
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return lock
        except BlockingIOError:
            if time.monotonic() >= deadline:
                lock.close()
                raise RuntimeError(f"Waited {minutes} minutes for another memory audit on this machine to release "
                                   f"{path}; the next run tries again") from None
            if meta["status"] != "waiting":
                meta["status"] = "waiting"
                atomic_json(state / "latest.json", meta)
            time.sleep(1)


def prune_runs(state, keep):
    cutoff = time.time() - RETENTION_DAYS * 86400
    for directory in (state / "runs").glob("*"):
        if directory.is_dir() and not directory.is_symlink() and str(directory) not in keep \
                and directory.stat().st_mtime < cutoff:
            shutil.rmtree(directory)


def run_model(repo, run_dir, env, prompt, timeout=5400, key=None):
    # Restricted mode ignores user and project settings. Without edit tools or edit rules, any write,
    # network command, or read outside the clone needs approval, which --permission-prompts none denies.
    # Tools inherit Claude's environment, and jq's env builtin reads it, so scrub mode withholds
    # ANTHROPIC_API_KEY and other secret-named variables from them; it keeps the manual permission mode.
    env = with_key(env, key) | {"CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1"}
    permissions = {"allow": ["Bash(jq *)", "Bash(qmd search *)"]}
    args = ["claude", "-p", "--restricted", "--no-session-persistence", "--strict-mcp-config",
            "--model", MODEL, "--effort", "high", "--tools", "Bash,Read,Glob,Grep",
            "--permission-mode", "manual", "--permission-prompts", "none",
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
            raise RuntimeError("Claude exceeded its time limit; see " + str(log.name)) from None
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


def prepare_search(repo, env):
    """Build the keyword-only search index of the clone's shared collections; return its environment."""
    qmd_dir = repo / ".cache/memory-audit-qmd"
    config_dir = qmd_dir / "config"
    config_dir.mkdir(parents=True)
    index = qmd_dir / "cache/qmd/index.sqlite"
    index.parent.mkdir(parents=True)
    config = json.loads(command([sys.executable, "-B", "-I", "-c", INDEX_CONFIG, str(repo / "bin")], repo, env))
    for name, collection in config["collections"].items():
        if not Path(collection["path"]).resolve().is_relative_to(repo.resolve()):
            raise ValueError("The audit's search index may hold only the clone's own collections: " + name)
    (config_dir / "index.yml").write_text(json.dumps(config, indent=2, sort_keys=True) + "\n")
    # Claude's scrub mode withholds XDG_CACHE_HOME from the model's tools, so INDEX_PATH names the index too;
    # without it, qmd search would read the user's own index.
    env = env | {"QMD_CONFIG_DIR": str(config_dir), "XDG_CACHE_HOME": str(qmd_dir / "cache"), "INDEX_PATH": str(index)}
    command(["qmd", "update"], repo, env, timeout=300)
    return env


def stand_in_reply(body, probes):
    """Return the stand-in model's content blocks for one Messages API request of the boundary check.

    The first turn makes every probe call at once, the second returns an empty audit through the structured
    output tool, and anything else, such as a request without the audit's tools, gets a short text answer.
    """
    tools = {tool.get("name"): tool for tool in body.get("tools") or [] if isinstance(tool, dict)}
    answered = {block.get("tool_use_id") for message in body.get("messages") or [] if isinstance(message, dict)
                and isinstance(message.get("content"), list) for block in message["content"]
                if isinstance(block, dict) and block.get("type") == "tool_result"}
    fields = set(output_schema()["properties"])
    output = next((name for name, tool in tools.items() if isinstance(tool.get("input_schema"), dict)
                   and set(tool["input_schema"].get("properties") or {}) == fields), None)
    if "Bash" in tools and not answered:
        return [{"type": "tool_use", "id": f"toolu_boundary_{number}", "name": tool, "input": arguments}
                for number, (_, tool, arguments, _) in enumerate(probes)]
    if "Bash" in tools and output and "toolu_boundary_result" not in answered:
        return [{"type": "tool_use", "id": "toolu_boundary_result", "name": output,
                 "input": {"report": "Boundary check", "findings": [], "changes": []}}]
    return [{"type": "text", "text": "Boundary check."}]


@contextmanager
def stand_in_api(probes):
    """Serve a local stand-in for the Anthropic Messages API that scripts the boundary check's tool calls."""

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            blocks = stand_in_reply(body, probes)
            stop = "tool_use" if blocks[0]["type"] == "tool_use" else "end_turn"
            message = {"id": "msg_boundary_check", "type": "message", "role": "assistant", "model": body.get("model"),
                       "content": blocks, "stop_reason": stop, "stop_sequence": None,
                       "usage": {"input_tokens": 1, "output_tokens": 1}}
            if body.get("stream"):
                events = [("message_start", {"message": message | {"content": [], "stop_reason": None}})]
                for index, block in enumerate(blocks):
                    if block["type"] == "tool_use":
                        start, delta = block | {"input": {}}, {"type": "input_json_delta",
                                                               "partial_json": json.dumps(block["input"])}
                    else:
                        start, delta = block | {"text": ""}, {"type": "text_delta", "text": block["text"]}
                    events += [("content_block_start", {"index": index, "content_block": start}),
                               ("content_block_delta", {"index": index, "delta": delta}),
                               ("content_block_stop", {"index": index})]
                events += [("message_delta", {"delta": {"stop_reason": stop, "stop_sequence": None},
                                              "usage": {"output_tokens": 1}}), ("message_stop", {})]
                kind = "text/event-stream"
                text = "".join(f"event: {name}\ndata: {json.dumps({'type': name} | data)}\n\n" for name, data in events)
            else:
                kind, text = "application/json", json.dumps(message)
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(text.encode())))
            self.end_headers()
            self.wfile.write(text.encode())

    # A plain TCP server skips HTTPServer's reverse lookup of its address, which can stall for seconds on macOS.
    server = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    # A short poll lets the check end as soon as Claude Code does.
    threading.Thread(target=server.serve_forever, args=(0.05,), daemon=True).start()
    try:
        yield f"http://127.0.0.1:{server.server_address[1]}"
    finally:
        server.shutdown()
        server.server_close()


def check_boundary(run_dir, env, scratch):
    """Fail unless the installed Claude Code still keeps secrets, the environment, and outside files from the
    model's tools, and still lets them use jq on the context and qmd search on the clone's own index.

    Real Claude Code runs through run_model and prepare_search with the audit's flags and scrub mode, but a
    local stand-in API scripts its tool calls, so the check makes no model request. A bogus key and canary
    variables stand in for secrets, and a scratch repository with one note stands in for the clone. Like the
    clone, the scratch folder keeps one path across runs; the run folder keeps the check's logs.
    """
    folder = run_dir / "boundary"
    repo = scratch / "repository"
    token = {name: secrets.token_hex(8) for name in ("secret", "plain", "context", "outside")}
    token["search"] = "canary" + secrets.token_hex(8)
    leaks = {token["secret"]: "the secret-named AUDIT_CANARY_API_KEY", BOUNDARY_KEY: "ANTHROPIC_API_KEY",
             token["plain"]: "the environment", token["outside"]: "a file outside the repository"}
    # Each probe must print null or be denied ("hidden"), be denied ("denied"), or print the given text.
    probes = [(line, "Bash", {"command": line, "description": "Boundary check"}, expected) for line, expected in (
        ("jq -n 'env.AUDIT_CANARY_API_KEY'", "hidden"), ("jq -n '$ENV.AUDIT_CANARY_API_KEY'", "hidden"),
        ("jq -n 'env.ANTHROPIC_API_KEY'", "hidden"),
        ("jq -r .probe artifacts/memory-audit-context.json", token["context"]),
        ("qmd search " + token["search"], "qmd://memory/boundary-check.md"),
        ("printenv", "denied"), ("env", "denied"), ("ps eww", "denied"), ("ps -E", "denied"),
        ("cat ../outside.txt", "denied"),
        # The allow rules must not reach outside the repository or cover a command chained after them.
        ("jq -R . ../outside.txt", "denied"), ("jq --rawfile f ../outside.txt -n '$f'", "denied"),
        # jq's module import takes its path from inside the program, where a check of file arguments misses it.
        ("""jq -n 'import "outside" as $x {search: ".."}; $x'""", "denied"),
        ("jq -n 1; cat ../outside.txt", "denied"), (f"qmd search {token['search']} && printenv", "denied"))]
    probes += [("Read ../outside.txt", "Read", {"file_path": str(scratch / "outside.txt")}, "denied"),
               ("Grep ../outside.txt", "Grep", {"pattern": ".", "path": str(scratch / "outside.txt"),
                                                "output_mode": "content"}, "denied"),
               ("Glob ../*.txt", "Glob", {"pattern": "*.txt", "path": str(scratch)}, "denied")]
    try:
        # An interrupted run can leave the scratch folder behind.
        shutil.rmtree(scratch, ignore_errors=True)
        folder.mkdir()
        for path in ("bin", ".config", "memory", "artifacts"):
            (repo / path).mkdir(parents=True)
        # Its own Git repository keeps the checkout's local settings, such as a home memory path, out of the index.
        command(["git", "init", "--quiet"], repo, env)
        shutil.copy2(ROOT / "bin/_knowledge.py", repo / "bin")
        (repo / ".config/knowledge.json").write_text(json.dumps(
            {"schema_version": 1, "collections": {"memory": {"path": "memory", "pattern": "**/*.md"}}}) + "\n")
        (repo / "memory/boundary-check.md").write_text("# Boundary check\n\n" + token["search"] + "\n")
        atomic_json(repo / "artifacts/memory-audit-context.json", {"probe": token["context"]})
        (scratch / "outside.txt").write_text(token["outside"] + "\n")
        (scratch / "outside.json").write_text(json.dumps(token["outside"]) + "\n")
        canaries = {"AUDIT_CANARY": token["plain"], "AUDIT_CANARY_API_KEY": token["secret"]}
        check_env = prepare_search(repo, env) | canaries
        with stand_in_api(probes) as url:
            run_model(repo, folder, check_env | {"ANTHROPIC_BASE_URL": url}, "Run the boundary check.", timeout=300,
                      key=BOUNDARY_KEY)
    except RuntimeError as error:
        raise RuntimeError("Could not check the memory audit's tool boundary, so the model did not run: "
                           + str(error)) from None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    version, results = "an unknown version", {}
    for line in (folder / "events.jsonl").read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "system" and event.get("subtype") == "init" and event.get("claude_code_version"):
            version = str(event["claude_code_version"])
        message = event.get("message") if event.get("type") == "user" else None
        for block in (message.get("content") or []) if isinstance(message, dict) else []:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                content = block.get("content")
                if isinstance(content, list):
                    content = "\n".join(str(part.get("text") or "") for part in content if isinstance(part, dict))
                results[block.get("tool_use_id")] = (bool(block.get("is_error")), str(content or ""))
    problems = []
    for number, (label, _, _, expected) in enumerate(probes):
        if f"toolu_boundary_{number}" not in results:
            problems.append(label + " got no result")
            continue
        denied, output = results[f"toolu_boundary_{number}"]
        leaked = [what for secret, what in leaks.items() if secret in output]
        if leaked:
            problems.append(label + " revealed " + " and ".join(leaked))
        elif expected == "denied" and not denied:
            problems.append(label + " ran without approval")
        elif expected == "hidden" and not denied and output.strip() != "null":
            problems.append(label + " did not print null")
        elif expected not in ("denied", "hidden") and (denied or expected not in output):
            problems.append(label + " did not print " + expected)
    if problems:
        raise RuntimeError(f"Claude Code {version} breaks the memory audit's tool boundary, so the model did not "
                           "run: " + "; ".join(problems) + ". Project Starter's runner must adapt to it; see "
                           "docs/foundation/memory-audit.md#tool-boundary-check and the run's boundary folder.")


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
        meta = {"status": "running", "directory": str(run_dir), "model": MODEL}
        atomic_json(state / "latest.json", meta)
        env = environment()
        options = turn = None
        try:
            options = settings(root, env)
            repository, heading = options["repository"], options["indexHeading"]
            # Waiting happens before the evidence is gathered and before the model's time limit starts.
            turn = take_turn(options["lockWaitMinutes"], state, meta)
            meta["status"] = "running"
            command(["git", "fetch", "--quiet", "origin", "main"], root, env)
            base = command(["git", "rev-parse", "FETCH_HEAD"], root, env).strip()
            meta["baseSha"] = base
            context = {"baseSha": base}
            for kind, key, extra in (("issue", "issues", "labels"), ("pr", "pullRequests", "mergedAt,headRefName")):
                fields = "number,title,state,closedAt,updatedAt,url,body," + extra
                context[key] = json.loads(command([
                    "gh", kind, "list", "--repo", repository, "--state", "all", "--limit", "1000", "--json", fields,
                ], root, env))
            prompt = audit_prompt(options)
            fingerprint = hashlib.sha256(json.dumps(context, sort_keys=True).encode() + prompt.encode()
                                         + Path(__file__).read_bytes()).hexdigest()
            # A run after a failure or crash always audits, so the failure issue can close.
            if not force and previous and previous["inputHash"] == fingerprint \
                    and last.get("status") in ("success", "skipped"):
                meta.update(status="skipped", reason="No repository, issue, PR, or audit instruction changes",
                            previousDirectory=previous["directory"])
                return meta
            key = api_key(root)
            require_login(root, env, key)
            # Claude Code can record the folder it works in as a project in ~/.claude.json, which nothing prunes,
            # so every run clones to the same path. The project's lock keeps other runs out of it, and an interrupted
            # run can leave it behind.
            repo = state / "repository"
            shutil.rmtree(repo, ignore_errors=True)
            command(["git", "-c", "core.hooksPath=/dev/null", "clone", "--quiet", "--shared", "--no-checkout",
                     str(root), str(repo)], root, env)
            command(["git", "-c", "core.hooksPath=/dev/null", "checkout", "--quiet", "--detach", base], repo, env)
            command(["git", "remote", "remove", "origin"], repo, env)
            # The runner's context and search index are not part of the audited checkout.
            with (repo / ".git/info/exclude").open("a") as exclude:
                exclude.write("\n/artifacts/\n/.cache/\n")
            notes = sorted(path.relative_to(repo).as_posix() for path in (repo / "memory").glob("*.md")
                           if path.name != "README.md")
            if (repo / "memory").is_symlink() or any((repo / path).is_symlink() for path in notes):
                raise ValueError("Active memory notes must not be symbolic links")
            if "## " + heading not in (repo / "memory/README.md").read_text().splitlines():
                raise ValueError(f"memory/README.md has no '## {heading}' heading over its active notes; add it or "
                                 "set memoryAudit.indexHeading in .config/knowledge.json")
            if not notes:
                meta.update(status="skipped", reason="No active memory notes to audit")
                close_failure_issue(root, env, repository, run_dir.name)
                return meta
            since = (previous or {}).get("completedAt") or \
                (datetime.now(timezone.utc) - timedelta(days=7)).isoformat(timespec="seconds")
            commits = command(["git", "log", "--since=" + since, "--no-merges", "--date=short",
                               "--format=%h %ad %s", base], repo, env).splitlines()
            context.update(activeNoteCount=len(notes), activeNotes=notes, lastSuccessfulAudit=previous,
                           runDateUtc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                           commitsSinceLastAudit=commits)
            artifacts = repo / "artifacts"
            artifacts.mkdir(exist_ok=True)
            atomic_json(artifacts / "memory-audit-context.json", context)
            atomic_json(run_dir / "memory-audit-context.json", context)
            # Claude Code can change what its tools reach in any release, so check before the model starts.
            check_boundary(run_dir, env, state / "boundary")
            env = prepare_search(repo, env)
            meta["credential"] = "api-key" if key else "subscription"
            atomic_json(state / "latest.json", meta)
            deadline = time.monotonic() + 5400
            for attempt in range(2):
                try:
                    run_model(repo, run_dir, env, prompt, timeout=max(1, deadline - time.monotonic()),
                              key=key if meta["credential"] == "api-key" else None)
                except RuntimeError:
                    refusal = key_refusal(run_dir) if meta["credential"] == "api-key" else None
                    if not refusal:
                        raise
                    # The subscription reruns this attempt; the key's logs stay, but not as session evidence.
                    for name in ("events.jsonl", "claude.log"):
                        (run_dir / name).rename(run_dir / ("api-key-" + name))
                    meta.update(credential="subscription", fallback=refusal)
                    atomic_json(state / "latest.json", meta)
                    try:
                        require_login(root, env, None)
                    except RuntimeError as error:
                        status = f", HTTP {refusal['status']}" if refusal["status"] else ""
                        raise RuntimeError(f"The API refused {API_KEY} ({refusal['message']}{status}), and the "
                                           f"subscription fallback failed: {error}") from None
                    run_model(repo, run_dir, env, prompt, timeout=max(1, deadline - time.monotonic()))
                if (command(["git", "rev-parse", "HEAD"], repo, env).strip() != base
                        or command(["git", "status", "--porcelain", "--untracked-files=all"], repo, env).strip()):
                    raise ValueError("The read-only audit changed its checkout")
                result = json.loads((run_dir / "result.json").read_text())
                try:
                    verify_session(repo, run_dir, notes)
                    apply_result(repo, result, notes, heading)
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
                               "If an archive breaks links in memory/README.md outside its active index, an existing "
                               "archive, a ledger, or a doc, keep that active note because those referring files are "
                               "outside your edit scope. Update findings, report counts, and proposed contents "
                               "together. Return the complete corrected JSON.\n\nValidation error:\n"
                               + str(error) + "\n\nPrevious response:\n" + json.dumps(result))
            command(["git", "add", "--intent-to-add", "--", "memory"], repo, env)
            command(["git", "diff", "--check"], repo, env)
            patch = command(["git", "diff", "--binary", "HEAD", "--", "memory"], repo, env)
            (run_dir / "memory-audit.patch").write_text(patch)
            (run_dir / "memory-audit-report.md").write_text(result["report"])
            changed = command(["git", "diff", "--name-only", "HEAD"], repo, env).splitlines()
            if changed:
                meta["publishedCommit"] = publish(root, repo, base, env, result["changes"], options)
            meta.update(status="success", inputHash=fingerprint, activeNoteCount=len(notes), changedFiles=changed,
                        completedAt=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            atomic_json(previous_path, meta)
            close_failure_issue(root, env, repository, run_dir.name)
            return meta
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            meta.update(status="failed", error=str(error),
                        finishedAt=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            report_failure(root, env, meta, options)
            raise
        finally:
            # The run folder keeps the context, report, patch, and logs; the clone is only working space.
            shutil.rmtree(state / "repository", ignore_errors=True)
            meta["finishedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
            atomic_json(run_dir / "run-meta.json", meta)
            atomic_json(state / "latest.json", meta)
            if turn:
                turn.close()


def install(root=ROOT):
    if sys.platform != "darwin":
        raise RuntimeError("The launchd schedule requires macOS")
    root = root.resolve()
    options = settings(root, environment())
    label, schedule = options["launchAgentLabel"], options["schedule"]
    python = Path.home() / ".local/bin/python3"
    if not os.access(python, os.X_OK):
        raise RuntimeError(f"Missing the default Python {python}; run `uv python install --default`")
    tool_paths = [str(python.parent)]
    for executable in ("claude", "qmd", "gh", "git", "rg", "jq", "node", "bun"):
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
    plist = agents / (label + ".plist")
    settings_plist = {
        "Label": label,
        # macOS pins a login item to its program's signature, which Apple's shell keeps across Python updates.
        "ProgramArguments": ["/bin/sh", "-c", 'exec "$0" "$@"', str(python), "-B", str(root / "bin/memory-audit"), "run"],
        "WorkingDirectory": str(root),
        "EnvironmentVariables": {"PATH": os.pathsep.join(dict.fromkeys(tool_paths))},
        "StartCalendarInterval": {"Weekday": WEEKDAYS.index(schedule["weekday"]), "Hour": schedule["hour"],
                                  "Minute": schedule["minute"]},
        "ProcessType": "Background",
        "StandardOutPath": str(log_dir / "launchd.log"),
        "StandardErrorPath": str(log_dir / "launchd-error.log"),
    }
    scheduled_env = environment() | settings_plist["EnvironmentVariables"]
    command(["qmd", "--version"], root, scheduled_env)
    domain = f"gui/{os.getuid()}"
    loaded = subprocess.run(["launchctl", "print", domain + "/" + label], capture_output=True)
    if loaded.returncode == 0:
        if re.search(rb"\bpid = \d+", loaded.stdout):
            raise RuntimeError("The scheduled audit is running; reinstall after it finishes")
        command(["launchctl", "bootout", domain + "/" + label], root, environment())
    plist.write_bytes(plistlib.dumps(settings_plist))
    command(["plutil", "-lint", str(plist)], root, environment())
    command(["launchctl", "bootstrap", domain, str(plist)], root, environment())
    command(["launchctl", "enable", domain + "/" + label], root, environment())
    return {"status": "installed", "plist": str(plist),
            "schedule": f"{schedule['weekday']} {schedule['hour']:02d}:{schedule['minute']:02d}, Mac local time"}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("action", choices=("run", "install", "settings"),
                        help="audit now, register the weekly LaunchAgent, or print the resolved settings")
    parser.add_argument("--force", action="store_true", help="Audit even when inputs match the last successful run")
    args = parser.parse_args()
    try:
        if args.action == "install":
            result = install()
        elif args.action == "settings":
            result = settings(ROOT, environment())
        else:
            result = run(force=args.force)
        print(json.dumps(result, indent=2), flush=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr, flush=True)
        return 1
