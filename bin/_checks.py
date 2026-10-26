"""Validate the documented Markdown subset and the portable foundation."""

import ast
from datetime import datetime, timedelta, timezone
import hashlib
import html
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import unicodedata
from urllib.parse import unquote, urlsplit

from _knowledge import git, matches


MARKERS = ("project-starter:begin", "project-starter:end")
# A passing application run stands for its clean tree and environment this long.
REUSE_WINDOW = timedelta(hours=12)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def managed_block(text):
    """Return the text between the Project Starter marker lines, or None without markers."""
    lines = text.splitlines(keepends=True)
    begins = [i for i, line in enumerate(lines) if MARKERS[0] in line]
    ends = [i for i, line in enumerate(lines) if MARKERS[1] in line]
    if not begins and not ends:
        return None
    if len(begins) != 1 or len(ends) != 1 or ends[0] < begins[0]:
        raise ValueError("expected one project-starter:begin line before one project-starter:end line")
    return "".join(lines[begins[0] + 1:ends[0]])


def manifest_errors(root):
    """Compare managed files and blocks with the hashes recorded by Project Starter's bin/sync."""
    path = root / ".project-starter.json"
    manifest = json.loads(path.read_text()) if path.is_file() else {}
    if "managed" not in manifest:
        return []
    overrides = manifest.get("overrides", {})
    errors = [".project-starter.json: override for " + relative + " needs a reason"
              for relative, reason in sorted(overrides.items()) if not isinstance(reason, str) or not reason.strip()]
    restore = ("; restore it with Project Starter's bin/sync or record an override with its reason"
               " in .project-starter.json")
    for kind, entries in (("file", manifest["managed"]), ("block", manifest.get("blocks", {}))):
        for relative, expected in sorted(entries.items()):
            if relative in overrides:
                continue
            file = root / relative
            try:
                content = None
                if file.is_file():
                    content = file.read_bytes() if kind == "file" else managed_block(file.read_text())
                if content is None:
                    errors.append(relative + ": managed " + kind + " is missing" + restore)
                elif digest(content if kind == "file" else content.encode()) != expected:
                    errors.append(relative + ": managed " + kind + " differs from Project Starter "
                                  + str(manifest.get("version")) + restore)
            except ValueError as error:
                errors.append(relative + ": " + str(error))
    return errors


def tracked_files(root):
    result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                            cwd=root, check=True, capture_output=True)
    return sorted({root / os.fsdecode(p) for p in result.stdout.split(b"\0") if p and (root / os.fsdecode(p)).is_file()})


def scalar(raw):
    raw = raw.strip()
    if raw.startswith('"'):
        value, end = json.JSONDecoder().raw_decode(raw)
        tail = raw[end:].strip()
        if not isinstance(value, str) or (tail and not tail.startswith("#")):
            raise ValueError("expected a one-line string")
        return value
    if raw.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", raw)
        if not match:
            raise ValueError("invalid single-quoted string")
        return match[1].replace("''", "'")
    value = re.split(r"\s+#", raw, maxsplit=1)[0].rstrip()
    if (not value or value[0] in "[]{}>|&*!%@`#" or ": " in value or
            value.lower() in {"null", "~", "true", "false"}):
        raise ValueError("expected plain text or a quoted one-line string; nested and multiline YAML are unsupported")
    return value


def metadata(text):
    match = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    if not match:
        raise ValueError("missing frontmatter")
    fields = {}
    for line in match[1].splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        entry = re.fullmatch(r"([a-z_]+):\s*(.*)", line)
        if not entry:
            raise ValueError("unsupported frontmatter line: " + line)
        key, raw = entry.groups()
        if key in fields:
            raise ValueError("duplicate frontmatter field: " + key)
        fields[key] = scalar(raw)
    return fields


def prose(text):
    text = re.sub(r"\A---\r?\n.*?\r?\n---(?:\r?\n|$)", "", text, count=1, flags=re.S)
    lines = []
    fence = None
    for line in text.splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
            lines.append("")
        elif marker:
            fence = marker[1]
            lines.append("")
        elif line.startswith("    ") or line.startswith("\t"):
            lines.append("")
        else:
            lines.append(line)
    return "\n".join(lines)


def anchors(text):
    body = prose(text)
    result = set(re.findall(r"<(?:a|[a-z][a-z0-9]*)\b[^>]*\b(?:id|name)=[\"']([^\"']+)[\"']", body, re.I))
    used = set()
    lines = body.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+)?\s*$", line)
        title = match[1] if match else None
        if not title and i and re.fullmatch(r" {0,3}(?:=+|-+)\s*", line) and lines[i - 1].strip():
            title = lines[i - 1].strip()
        if not title:
            continue
        title = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", title)
        title = html.unescape(re.sub(r"<[^>]+>", "", title)).lower()
        slug = "".join(c for c in title if c in " -_" or unicodedata.category(c)[0] in "LMN")
        slug = slug.replace(" ", "-")
        candidate, suffix = slug, 0
        while candidate in used:
            suffix += 1
            candidate = slug + "-" + str(suffix)
        used.add(candidate)
        result.add(candidate)
    return result


def destination(raw):
    raw = raw.strip()
    if raw.startswith("<"):
        end = raw.find(">")
        if end < 0:
            raise ValueError("unterminated angle-bracket link")
        target, tail = raw[1:end], raw[end + 1:].strip()
    else:
        pieces = raw.split(maxsplit=1)
        if not pieces:
            return ""
        target, tail = pieces[0], pieces[1] if len(pieces) == 2 else ""
    if tail and not ((tail[0], tail[-1]) in {( '"', '"'), ("'", "'"), ("(", ")")}):
        raise ValueError("unsupported link destination; put paths with spaces in <angle brackets>")
    return re.sub(r"\\([\\()\[\] ])", r"\1", target)


def link_targets(text):
    body = re.sub(r"(`+).*?\1", "", prose(text))
    targets = []
    # Parse nested parentheses in inline destinations, rather than stopping at
    # the first ')' in a legitimate filename.
    for match in re.finditer(r"(?<!\\)\]\(", body):
        start = position = match.end()
        depth, angle, quote = 1, False, None
        while position < len(body):
            char = body[position]
            if char == "\\":
                position += 2
                continue
            if quote:
                if char == quote:
                    quote = None
            elif angle:
                if char == ">":
                    angle = False
            elif char == "<":
                angle = True
            elif char in "\"'" and position > start and body[position - 1].isspace():
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if not depth:
                    targets.append(destination(body[start:position]))
                    break
            position += 1
        else:
            raise ValueError("unterminated Markdown link destination")
    definitions = {}
    for match in re.finditer(r"(?m)^ {0,3}\[([^\]]+)\]:\s*(.+)$", body):
        label = " ".join(match[1].lower().split())
        definitions[label] = destination(match[2])
        targets.append(definitions[label])
    for match in re.finditer(r"\[([^\]]+)\]\[([^\]]*)\]", body):
        label = " ".join((match[2] or match[1]).lower().split())
        if label not in definitions:
            raise ValueError("undefined reference link: " + label)
    return targets


def local_target(page, target):
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc:
        return None, ""
    return ((page.parent / unquote(parsed.path)).resolve() if parsed.path else page.resolve(), unquote(parsed.fragment))


def validate(root, areas=("memory", "docs"), options=None):
    config = options if options is not None else json.loads((root / ".config/knowledge.json").read_text())
    exclusions = config.get("checks", {}).get("exclude", [])
    files = tracked_files(root)
    markdown = [p for p in files if p.suffix == ".md" and not matches(p.relative_to(root).as_posix(), exclusions)]
    errors, active, archived, parsed_links = [], {area: set() for area in areas}, set(), {}
    for page in markdown:
        relative = page.relative_to(root)
        text = page.read_text()
        area = relative.parts[0]
        if area in active and page.name != "README.md":
            try:
                fields = metadata(text)
                in_archive = len(relative.parts) > 1 and relative.parts[1] == "archive"
                if area == "memory":
                    if set(fields) - {"name", "description", "type", "status"}:
                        raise ValueError("unsupported memory fields")
                    if fields.get("name") != page.stem or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", page.stem):
                        raise ValueError("memory name must match its kebab-case filename")
                    if not fields.get("description", "").strip():
                        raise ValueError("memory description must not be empty")
                    if fields.get("type") not in {"user", "feedback", "project", "reference"}:
                        raise ValueError("invalid memory type")
                    if fields["type"] == "project":
                        expected = "resolved" if in_archive else "active"
                        if fields.get("status") != expected:
                            raise ValueError("project memory status must be " + expected)
                    elif "status" in fields:
                        raise ValueError("only project memories have status")
                else:
                    if set(fields) != {"status"}:
                        raise ValueError("document frontmatter must contain only status")
                    allowed = {"superseded", "archived"} if in_archive else {"draft", "current"}
                    if fields["status"] not in allowed:
                        raise ValueError("document status must be " + "/".join(sorted(allowed)) + " in this location")
                if not re.search(r"(?m)^#\s+\S", prose(text)):
                    raise ValueError("ordinary pages need a top-level title")
                (archived if in_archive else active[area]).add(page.resolve())
            except ValueError as error:
                errors.append(str(relative) + ": " + str(error))
        try:
            parsed_links[page.resolve()] = link_targets(text)
            for target in parsed_links[page.resolve()]:
                resolved, fragment = local_target(page, target)
                if resolved is None:
                    continue
                if not resolved.exists():
                    errors.append(str(relative) + ": missing link destination " + target)
                elif fragment and resolved.suffix == ".md" and fragment not in anchors(resolved.read_text()):
                    errors.append(str(relative) + ": missing heading anchor " + target)
        except ValueError as error:
            errors.append(str(relative) + ": " + str(error))
    for area, expected in active.items():
        start = (root / area / "README.md").resolve()
        visited, covered, todo = set(), set(), [start]
        if not start.is_file():
            errors.append(area + "/README.md: missing knowledge index")
        while todo:
            page = todo.pop()
            if page in visited:
                continue
            visited.add(page)
            for target in parsed_links.get(page, []):
                resolved, _ = local_target(page, target)
                if resolved is None or not resolved.is_relative_to((root / area).resolve()):
                    continue
                if resolved in archived:
                    errors.append(str(page.relative_to(root)) + ": archived page in active index: " + str(resolved.relative_to(root)))
                elif resolved.name == "README.md" and "archive" not in resolved.relative_to(root / area).parts:
                    todo.append(resolved)
                else:
                    covered.add(resolved)
        for page in sorted(expected - covered):
            errors.append(str(page.relative_to(root)) + ": active page missing from " + area + "/README.md or a linked README index")
    return errors


def environment(root):
    """Fingerprint what besides the tree can change application results."""
    # platform.platform() differs between Python releases on the same machine.
    facts = {"platform": " ".join((platform.system(), platform.release(), platform.machine()))}
    for tool in ("python3", "node"):
        if shutil.which(tool):
            result = subprocess.run([tool, "--version"], text=True, capture_output=True)
            facts[tool] = (result.stdout + result.stderr).strip()
    venv = root / ".venv"
    if venv.is_dir():
        configuration = venv / "pyvenv.cfg"
        facts["venv"] = configuration.read_text() if configuration.is_file() else ""
        # Distribution folders name each installed package and its version.
        facts["packages"] = sorted(path.name for path in venv.glob("lib/*/site-packages/*.*-info"))
    lock = root / "node_modules/.package-lock.json"
    if lock.is_file():
        facts["node_modules"] = digest(lock.read_bytes())
    return digest(json.dumps(facts, sort_keys=True).encode())


def clean_tree(root):
    """Return the tree of a checkout with no uncommitted or untracked changes, or None."""
    if git("status", "--porcelain", "--untracked-files=all", root=root):
        return None
    return git("rev-parse", "--verify", "--quiet", "HEAD^{tree}", root=root, optional=True) or None


def pass_record(root, tree):
    folder = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", root=root)) / "project-starter/check-passes"
    return folder / (tree + ".json")


def reusable_pass(root, tree, fingerprint):
    """Return a recent passing application run for this tree and environment, or None."""
    try:
        record = json.loads(pass_record(root, tree).read_text())
        passed = datetime.fromisoformat(record["passed_at"])
    except (OSError, ValueError, KeyError, TypeError):
        return None
    if record.get("environment") != fingerprint or datetime.now(timezone.utc) - passed > REUSE_WINDOW:
        return None
    return record


def record_pass(root, tree, fingerprint):
    path = pass_record(root, tree)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Expired records can never be reused, so they don't accumulate.
    expired = datetime.now().timestamp() - REUSE_WINDOW.total_seconds()
    for old in path.parent.glob("*.json"):
        if old.stat().st_mtime < expired:
            old.unlink(missing_ok=True)
    temporary = path.with_name("." + path.name + "." + str(os.getpid()))
    temporary.write_text(json.dumps({"tree": tree, "commit": git("rev-parse", "HEAD", root=root),
                                     "passed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                                     "environment": fingerprint}) + "\n")
    temporary.replace(path)


def application_checks(root, application, reuse):
    """Run bin/check-application, or reuse its recent pass on the same clean tree and environment."""
    tree = clean_tree(root)
    fingerprint = environment(root) if tree else None
    record = reusable_pass(root, tree, fingerprint) if tree and reuse else None
    if record:
        passed = datetime.fromisoformat(record["passed_at"]).astimezone().strftime("%Y-%m-%d %H:%M")
        print("Reused the application checks that passed at " + passed + " on commit " + record["commit"][:12] +
              " for this clean tree and environment; bin/check --full --no-reuse runs them again.", flush=True)
        return
    subprocess.run([str(application)], cwd=root, check=True)
    # Record only a run whose checkout stayed clean at the same tree.
    if tree and clean_tree(root) == tree:
        try:
            record_pass(root, tree, fingerprint)
        except OSError as error:
            print("Could not record the passing application checks for reuse: " + str(error), file=sys.stderr)


def main():
    root = Path(__file__).resolve().parents[1]
    try:
        if sys.argv[1:] not in ([], ["--documents-only"], ["--full"], ["--full", "--no-reuse"]):
            raise ValueError("Usage: bin/check [--documents-only | --full [--no-reuse]]")
        errors = manifest_errors(root) + validate(root)
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print("Document metadata, index coverage, and local links passed.", flush=True)
        if sys.argv[1:] == ["--documents-only"]:
            return 0
        if not shutil.which("shellcheck"):
            raise RuntimeError("ShellCheck is required for bin/check. Install it with your package manager.")
        shell_files = []
        for path in tracked_files(root):
            if path == root / ".envrc":
                subprocess.run(["shellcheck", "--shell=bash", str(path)], cwd=root, check=True)
            elif path.is_relative_to(root / "bin") and path.read_bytes().startswith(b"#!/bin/sh"):
                shell_files.append(path)
            elif (path.is_relative_to(root / "bin") or path.is_relative_to(root / "tests")) and (path.suffix == ".py" or path.read_bytes().startswith(b"#!/usr/bin/env python3")):
                ast.parse(path.read_text(), filename=str(path))
        if shell_files:
            subprocess.run(["shellcheck", "--shell=sh", *map(str, shell_files)], cwd=root, check=True)
        subprocess.run(["git", "diff", "--check"], cwd=root, check=True)
        subprocess.run(["git", "diff", "--cached", "--check"], cwd=root, check=True)
        if sys.argv[1:2] != ["--full"]:
            print("Fast foundation checks passed. Use bin/check --full for application validation.", flush=True)
            return 0
        application = root / "bin/check-application"
        if not application.exists():
            print("Full foundation checks passed; no bin/check-application is present.", flush=True)
            return 0
        if not os.access(application, os.X_OK):
            raise RuntimeError("bin/check-application must be executable")
        application_checks(root, application, reuse="--no-reuse" not in sys.argv)
        print("Full foundation and application checks passed.", flush=True)
        return 0
    except (OSError, ValueError, RuntimeError, SyntaxError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
