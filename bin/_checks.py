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

from _knowledge import git, git_environment, matches


MARKERS = ("project-starter:begin", "project-starter:end")
# A passing application run stands for its clean tree and environment this long.
REUSE_WINDOW = timedelta(hours=12)
# A shebang naming a ShellCheck dialect, directly or through env, with or without flags.
SHELL_SHEBANG = re.compile(rb"#![ \t]*(?:\S*/)?(?:env[ \t]+(?:-\S*[ \t]+)*)?(sh|bash|dash|ksh)(?=\s|$)")


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


def event_base():
    """Return the revision a GitHub Actions pull request or push run starts from, or None for any other run.

    That is the pull request's base branch, or the commit a push replaced. A push that creates its branch has none.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return None
    name = os.environ.get("GITHUB_EVENT_NAME")
    if name == "pull_request" and os.environ.get("GITHUB_BASE_REF"):
        return "refs/remotes/origin/" + os.environ["GITHUB_BASE_REF"]
    if name == "push":
        before = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()).get("before") or ""
        return before if before.strip("0") else None
    return None


def change_base(root):
    """Return where this checkout's own changes start, or None when its history can't tell.

    In a GitHub Actions pull request or push run, that is the fork point from its event's base. Otherwise it is
    the fork point from origin's default branch, or the empty tree before anything is fetched or pushed.
    A clone without that history, such as one whose push rewrote what it replaced, gets None rather than the
    empty tree, so content already on the default branch never fails the check. A shallow GitHub Actions
    checkout that can't reach its event's base fails instead, since it would check nothing committed.
    """
    if not git("rev-parse", "--verify", "--quiet", "HEAD^{commit}", root=root, optional=True):
        return None
    shallow = git("rev-parse", "--is-shallow-repository", root=root) == "true"
    event = event_base()
    if event:
        commit = git("rev-parse", "--verify", "--quiet", event + "^{commit}", root=root, optional=True)
        base = commit and git("merge-base", "HEAD", commit, root=root, optional=True)
        if base:
            return base
        if shallow:
            raise RuntimeError("This shallow checkout can't reach " + event + ", where this run's commits start, so "
                               "the whitespace check would read none of them. Give actions/checkout fetch-depth: 0, "
                               "as docs/foundation/engineering-policy.md#hosted-ci describes.")
    default = git("rev-parse", "--verify", "--quiet", "refs/remotes/origin/HEAD^{commit}", root=root, optional=True)
    if default:
        return git("merge-base", "HEAD", default, root=root, optional=True) or None
    if shallow or git("for-each-ref", "--count=1", "--format=%(refname)", "refs/remotes", root=root):
        return None
    return git("hash-object", "-t", "tree", os.devnull, root=root)


def hosted_partial_clone(root):
    """Return whether this is a GitHub Actions checkout that leaves objects on its server, as a sparse checkout does."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return False
    promisors = git("config", "--type=bool", "--get-regexp", r"^remote\..*\.promisor$", root=root, optional=True)
    return bool(git("config", "--get", "extensions.partialClone", root=root, optional=True)
                or any(line.endswith(" true") for line in promisors.splitlines()))


def base_blobs(root, base):
    """Return the changed paths that the sparse checkout leaves out, and base's blobs of the other changed paths that
    the whitespace check reads but this clone lacks, without fetching anything. With no base, the changes are the
    working tree's against the index.

    The checkout's own patterns decide what it leaves out, so a path stays out after a step writes a file there, and
    whatever its content. The check skips deletions, which add no lines, but when the run adds a file, Git's rename
    detection reads each deleted file's base to look for a pair, so whitespace a run only moves still passes.
    """
    environment = git_environment() | {"GIT_NO_LAZY_FETCH": "1"}

    def fields(*args, paths=()):
        result = subprocess.run(["git", *args], cwd=root, env=environment, capture_output=True,
                                input=b"".join(os.fsencode(path) + b"\0" for path in paths))
        if result.returncode:
            raise RuntimeError(os.fsdecode(result.stderr).strip() or "Git command failed")
        return [os.fsdecode(field) for field in result.stdout.split(b"\0")[:-1]]

    # Unlike git diff, the diff-* commands read no blob to rule out a file whose stat information alone is stale.
    listed = fields(*(("diff-index", base) if base else ("diff-files",)), "-z", "--no-renames", "--no-abbrev")
    # Each change is ":<base mode> <mode> <base object> <object> <status>", then its path.
    changes = {path: header[1:].split()[:3] for header, path in zip(listed[0::2], listed[1::2])}
    excluded = set()
    if git("config", "--type=bool", "--get", "core.sparseCheckout", root=root, optional=True) == "true":
        # check-rules prints each path that the patterns, cone or not, keep, and reads no objects.
        excluded = changes.keys() - set(fields("sparse-checkout", "check-rules", "-z", paths=changes))
    checked = [modes for path, modes in changes.items() if path not in excluded]
    adds = any(base_mode == "000000" for base_mode, _, _ in checked)
    names = sorted({name for base_mode, mode, name in checked
                    if base_mode not in ("000000", "160000") and (mode != "000000" or adds)})
    probe = subprocess.run(["git", "cat-file", "--batch-check=%(objectname)"], cwd=root, env=environment, check=True,
                           capture_output=True, text=True, input="".join(name + "\n" for name in names))
    return sorted(excluded), [line.split()[0] for line in probe.stdout.splitlines() if line.endswith(" missing")]


def check_whitespace(root):
    """Run Git's whitespace check on staged changes and on the working tree since the change base."""
    base = change_base(root)
    environment, excluded = git_environment(), []
    if hosted_partial_clone(root):
        # The check's step holds no credentials, so it reads only what the checkout has, and skips what it left out.
        environment |= {"GIT_NO_LAZY_FETCH": "1"}
        excluded, missing = base_blobs(root, base)
        if missing:
            files = "1 changed file" if len(missing) == 1 else str(len(missing)) + " changed files"
            raise RuntimeError("This partial clone lacks the base version of " + files + " that the whitespace check "
                               "reads, and the check fetches nothing, since its step has no credentials. Run "
                               "bin/check --fetch-base with the job's token in a step before it, as "
                               "docs/foundation/engineering-policy.md#hosted-ci describes.")
    paths = ["--", *(":(top,literal,exclude)" + path for path in excluded)] if excluded else []
    # Comparing the base with the working tree covers commits since it, and a fix counts once it's made. A deletion
    # adds no lines, so Git reads a deleted file's base only for rename detection, when the run adds a file.
    subprocess.run(["git", "diff", "--check", "--diff-filter=d", *([base] if base else []), *paths], cwd=root,
                   env=environment, check=True)
    subprocess.run(["git", "diff", "--cached", "--check"], cwd=root, env=environment, check=True)


def fetch_base(root):
    """Fetch from origin the base blobs the whitespace check reads in a GitHub Actions partial clone, if any.

    GH_TOKEN, when set, reaches only this fetch, through a credential helper that reads it from the environment.
    """
    base = change_base(root) if hosted_partial_clone(root) else None
    missing = base_blobs(root, base)[1] if base else []
    if not missing:
        print("The whitespace check has every base file it reads; nothing to fetch.", flush=True)
        return
    environment = git_environment() | {"GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0"}
    if os.environ.get("GH_TOKEN"):
        count = int(os.environ.get("GIT_CONFIG_COUNT") or 0)
        # The empty value drops any configured helpers, so none asks elsewhere or stores the token.
        helpers = ("", '!f() { test "$1" = get && printf "username=x-access-token\\npassword=%s\\n" "$GH_TOKEN"; }; f')
        for index, helper in enumerate(helpers, count):
            environment |= {"GIT_CONFIG_KEY_%d" % index: "credential.helper", "GIT_CONFIG_VALUE_%d" % index: helper}
        environment["GIT_CONFIG_COUNT"] = str(count + len(helpers))
    files = "1 changed file" if len(missing) == 1 else str(len(missing)) + " changed files"
    # These are the options Git's own lazy fetch uses, so only the named blobs arrive.
    fetched = subprocess.run(["git", "-c", "fetch.negotiationAlgorithm=noop", "fetch", "--quiet", "--no-tags",
                              "--no-write-fetch-head", "--recurse-submodules=no", "--filter=blob:none", "--stdin",
                              "origin"], cwd=root, env=environment, text=True,
                             input="".join(blob + "\n" for blob in missing))
    if fetched.returncode:
        raise RuntimeError("Could not fetch the base version of " + files + " from origin. A private repository "
                           "needs the job's token in this step, as GH_TOKEN: ${{ github.token }}; see "
                           "docs/foundation/engineering-policy.md#hosted-ci.")
    print("Fetched the base version of " + files + " for the whitespace check.", flush=True)


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
        if sys.argv[1:] not in ([], ["--documents-only"], ["--full"], ["--full", "--no-reuse"], ["--fetch-base"]):
            raise ValueError("Usage: bin/check [--documents-only | --full [--no-reuse] | --fetch-base]")
        if sys.argv[1:] == ["--fetch-base"]:
            fetch_base(root)
            return 0
        errors = manifest_errors(root) + validate(root)
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print("Document metadata, index coverage, and local links passed.", flush=True)
        if sys.argv[1:] == ["--documents-only"]:
            return 0
        if not shutil.which("shellcheck"):
            raise RuntimeError("ShellCheck is required for bin/check. Install it with your package manager.")
        shell_files = {}
        for path in tracked_files(root):
            shell = SHELL_SHEBANG.match(path.read_bytes()) if path.is_relative_to(root / "bin") else None
            if path == root / ".envrc":
                shell_files.setdefault("bash", []).append(path)
            elif shell:
                shell_files.setdefault(shell[1].decode(), []).append(path)
            elif (path.is_relative_to(root / "bin") or path.is_relative_to(root / "tests")) and (path.suffix == ".py" or path.read_bytes().startswith(b"#!/usr/bin/env python3")):
                ast.parse(path.read_text(), filename=str(path))
        for shell, paths in sorted(shell_files.items()):
            subprocess.run(["shellcheck", "--shell=" + shell, *map(str, paths)], cwd=root, check=True)
        check_whitespace(root)
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
