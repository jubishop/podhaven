"""Validate the documented Markdown subset and the portable foundation."""

import ast
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import unicodedata
from urllib.parse import unquote, urlsplit

from _knowledge import matches


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


def main():
    root = Path(__file__).resolve().parents[1]
    try:
        if sys.argv[1:] not in ([], ["--documents-only"], ["--full"]):
            raise ValueError("Usage: bin/check [--documents-only | --full]")
        errors = validate(root)
        from _memory_index import update
        try:
            update(root, check=True)
        except ValueError as error:
            errors.append(str(error))
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
        if sys.argv[1:] == ["--full"]:
            tests = root / "bin/tests/test_knowledge.py"
            if not tests.exists():
                raise RuntimeError("Missing bin/tests/test_knowledge.py; preserve the foundation tests when adapting bin/check")
            subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "bin/tests", "-p", "test_*.py", "-v"], cwd=root, check=True)
            print("Full repository foundation checks passed.", flush=True)
        else:
            print("Fast foundation checks passed. Use bin/check --full for behavior tests.", flush=True)
        return 0
    except (OSError, ValueError, RuntimeError, SyntaxError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
