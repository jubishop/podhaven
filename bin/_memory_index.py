"""Regenerate only the active-note list; preserve the surrounding policy."""

from pathlib import Path
import re

from _checks import metadata, prose

START = "<!-- ACTIVE_MEMORY_START -->"
END = "<!-- ACTIVE_MEMORY_END -->"


def rendered_index(root):
    path = root / "memory/README.md"
    text = path.read_text()
    if text.count(START) != 1 or text.count(END) != 1 or text.index(START) > text.index(END):
        raise ValueError("memory/README.md needs one ordered pair of active-memory markers")
    entries = []
    for page in sorted((root / "memory").glob("*.md")):
        if page.name == "README.md":
            continue
        fields = metadata(page.read_text())
        if fields.get("name") != page.stem or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", page.stem):
            raise ValueError(str(page) + ": memory name must match its kebab-case filename")
        title = re.search(r"(?m)^#\s+(.+)$", prose(page.read_text()))
        if not title or not fields.get("description"):
            raise ValueError(str(page) + ": title and description are required")
        def escape(value):
            return re.sub(r"([\\`*{}\[\]<>])", r"\\\1", value)
        entries.append("- [" + escape(title[1]) + "](" + page.name + "): " + escape(fields["description"]))
    return text.split(START)[0] + START + "\n\n" + "\n".join(entries) + "\n\n" + END + text.split(END)[1]


def update(root, check=False):
    path = root / "memory/README.md"
    expected = rendered_index(root)
    if expected != path.read_text():
        if check:
            raise ValueError("Active memory index is stale; run bin/memory-index")
        path.write_text(expected)
