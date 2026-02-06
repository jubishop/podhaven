#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_PROJECTS_DIR = Path.home() / ".claude" / "projects"


@dataclass
class ConversationMeta:
    path: Path
    session_id: str | None
    cwd: str | None
    title: str
    user_messages: int
    assistant_messages: int
    total_records: int
    first_ts: datetime | None
    last_ts: datetime | None


@dataclass
class TranscriptEntry:
    role: str
    timestamp: datetime | None
    text: str


def parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None

    text = value.strip()
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"

    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def iter_jsonl(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            raw = line.strip()
            if not raw:
                continue
            try:
                yield json.loads(raw)
            except json.JSONDecodeError as error:
                print(
                    f"Warning: Skipping invalid JSON in {path} line {line_number}: {error}",
                    file=sys.stderr,
                )


def pick_record_timestamp(record: dict[str, Any]) -> datetime | None:
    direct = parse_timestamp(record.get("timestamp"))
    if direct:
        return direct

    data = record.get("data")
    if isinstance(data, dict):
        message = data.get("message")
        if isinstance(message, dict):
            nested = parse_timestamp(message.get("timestamp"))
            if nested:
                return nested

    return None


def normalize_text(value: str) -> str:
    normalized = value.replace("\r\n", "\n").replace("\r", "\n").strip()
    return normalized


def is_local_command_envelope(text: str) -> bool:
    prefixes = (
        "<local-command-",
        "<command-name>",
        "<command-message>",
        "<command-args>",
    )
    return text.startswith(prefixes)


def extract_user_text(message: Any) -> list[str]:
    if not isinstance(message, dict):
        return []

    content = message.get("content")
    if isinstance(content, str):
        text = normalize_text(content)
        if text and not is_local_command_envelope(text):
            return [text]
        return []

    if not isinstance(content, list):
        return []

    texts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "text":
            continue
        value = block.get("text")
        if isinstance(value, str):
            cleaned = normalize_text(value)
            if cleaned and not is_local_command_envelope(cleaned):
                texts.append(cleaned)
    return texts


def extract_assistant_text(message: Any, include_thinking: bool) -> list[str]:
    if not isinstance(message, dict):
        return []

    content = message.get("content")
    if not isinstance(content, list):
        return []

    texts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue

        block_type = block.get("type")
        if block_type == "text":
            value = block.get("text")
            if isinstance(value, str):
                cleaned = normalize_text(value)
                if cleaned:
                    texts.append(cleaned)
            continue

        if include_thinking and block_type == "thinking":
            value = block.get("thinking")
            if isinstance(value, str):
                cleaned = normalize_text(value)
                if cleaned:
                    texts.append(f"[thinking]\n{cleaned}")
    return texts


def discover_conversation_files(projects_dir: Path) -> list[Path]:
    if not projects_dir.exists():
        return []
    return sorted(projects_dir.glob("*/*.jsonl"))


def summarize_conversation(path: Path) -> ConversationMeta:
    session_id: str | None = None
    cwd: str | None = None
    first_user_text: str | None = None
    summary_text: str | None = None
    user_messages = 0
    assistant_messages = 0
    total_records = 0
    first_ts: datetime | None = None
    last_ts: datetime | None = None

    for record in iter_jsonl(path):
        total_records += 1

        record_ts = pick_record_timestamp(record)
        if record_ts is not None:
            if first_ts is None or record_ts < first_ts:
                first_ts = record_ts
            if last_ts is None or record_ts > last_ts:
                last_ts = record_ts

        if session_id is None and isinstance(record.get("sessionId"), str):
            session_id = record["sessionId"]

        if isinstance(record.get("cwd"), str):
            cwd = record["cwd"]

        record_type = record.get("type")

        if record_type == "summary":
            summary = record.get("summary")
            if isinstance(summary, str):
                cleaned = normalize_text(summary)
                if cleaned:
                    summary_text = cleaned
            continue

        if record_type == "user":
            user_messages += 1
            if first_user_text is None:
                chunks = extract_user_text(record.get("message"))
                if chunks:
                    first_user_text = chunks[0]
            continue

        if record_type == "assistant":
            assistant_messages += 1

    title = summary_text or first_user_text or path.stem
    if len(title) > 110:
        title = f"{title[:107]}..."

    return ConversationMeta(
        path=path,
        session_id=session_id,
        cwd=cwd,
        title=title,
        user_messages=user_messages,
        assistant_messages=assistant_messages,
        total_records=total_records,
        first_ts=first_ts,
        last_ts=last_ts,
    )


def to_local(dt: datetime | None) -> str:
    if dt is None:
        return "-"
    return dt.astimezone().strftime("%Y-%m-%d %H:%M")


def ellipsize(text: str | None, width: int) -> str:
    if not text:
        return "-"
    if len(text) <= width:
        return text
    if width < 4:
        return text[:width]
    return f"{text[:width - 3]}..."


def load_conversations(projects_dir: Path, cwd_contains: str | None) -> list[ConversationMeta]:
    files = discover_conversation_files(projects_dir)
    conversations = [summarize_conversation(path) for path in files]

    if cwd_contains:
        lowered = cwd_contains.lower()
        conversations = [
            item
            for item in conversations
            if item.cwd and lowered in item.cwd.lower()
        ]

    conversations.sort(key=lambda item: item.last_ts or datetime.min, reverse=True)
    return conversations


def list_conversations(args: argparse.Namespace) -> int:
    conversations = load_conversations(args.projects_dir, args.cwd_contains)

    if args.limit:
        conversations = conversations[: args.limit]

    if args.json:
        payload = []
        for index, item in enumerate(conversations, start=1):
            payload.append(
                {
                    "index": index,
                    "path": str(item.path),
                    "sessionId": item.session_id,
                    "cwd": item.cwd,
                    "title": item.title,
                    "userMessages": item.user_messages,
                    "assistantMessages": item.assistant_messages,
                    "totalRecords": item.total_records,
                    "firstTimestamp": item.first_ts.isoformat() if item.first_ts else None,
                    "lastTimestamp": item.last_ts.isoformat() if item.last_ts else None,
                }
            )
        print(json.dumps(payload, indent=2))
        return 0

    print(f"Claude conversations in {args.projects_dir}")
    if not conversations:
        print("No conversations found.")
        return 0

    header = f"{'Idx':>3}  {'Updated':16}  {'Msgs':>9}  {'CWD':38}  Title"
    print(header)
    print("-" * len(header))

    for index, item in enumerate(conversations, start=1):
        msgs = f"{item.user_messages}/{item.assistant_messages}"
        cwd = ellipsize(item.cwd, 38)
        title = ellipsize(item.title, 110)
        print(
            f"{index:>3}  {to_local(item.last_ts):16}  {msgs:>9}  {cwd:38}  {title}"
        )
    return 0


def select_conversation(args: argparse.Namespace) -> ConversationMeta:
    conversations = load_conversations(args.projects_dir, args.cwd_contains)
    if not conversations:
        raise ValueError(f"No Claude conversations found in {args.projects_dir}")

    if args.index is not None:
        if args.index < 1 or args.index > len(conversations):
            raise ValueError(f"Index {args.index} is out of range 1..{len(conversations)}")
        return conversations[args.index - 1]

    if args.session_id is not None:
        for item in conversations:
            if item.session_id == args.session_id:
                return item
        raise ValueError(f"No conversation found with session ID: {args.session_id}")

    if args.file is not None:
        candidate = args.file.expanduser().resolve()
        for item in conversations:
            if item.path.resolve() == candidate:
                return item
        raise ValueError(f"Conversation file not found in index: {args.file}")

    raise ValueError("One selector is required: --index, --session-id, or --file")


def build_transcript(
    path: Path,
    include_thinking: bool,
) -> tuple[list[TranscriptEntry], list[str], set[str]]:
    entries: list[TranscriptEntry] = []
    summaries: list[str] = []
    models: set[str] = set()

    for record in iter_jsonl(path):
        record_type = record.get("type")

        if record_type == "summary":
            value = record.get("summary")
            if isinstance(value, str):
                cleaned = normalize_text(value)
                if cleaned:
                    summaries.append(cleaned)
            continue

        timestamp = pick_record_timestamp(record)
        if record_type == "user":
            chunks = extract_user_text(record.get("message"))
            if not chunks:
                continue
            entries.append(
                TranscriptEntry(role="user", timestamp=timestamp, text="\n\n".join(chunks))
            )
            continue

        if record_type == "assistant":
            message = record.get("message")
            if isinstance(message, dict):
                model = message.get("model")
                if isinstance(model, str):
                    models.add(model)

            chunks = extract_assistant_text(message, include_thinking=include_thinking)
            if not chunks:
                continue
            entries.append(
                TranscriptEntry(
                    role="assistant",
                    timestamp=timestamp,
                    text="\n\n".join(chunks),
                )
            )

    return entries, summaries, models


def format_resume_packet(
    meta: ConversationMeta,
    transcript: list[TranscriptEntry],
    summaries: list[str],
    models: set[str],
) -> str:
    now = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    lines: list[str] = []

    lines.append("# Claude Conversation Resume Packet")
    lines.append("")
    lines.append(f"- Generated: {now}")
    lines.append(f"- Source file: `{meta.path}`")
    lines.append(f"- Session ID: `{meta.session_id or '-'}`")
    lines.append(f"- CWD: `{meta.cwd or '-'}`")
    lines.append(f"- First timestamp: `{meta.first_ts.isoformat() if meta.first_ts else '-'}`")
    lines.append(f"- Last timestamp: `{meta.last_ts.isoformat() if meta.last_ts else '-'}`")
    lines.append(
        f"- Message counts (user/assistant): `{meta.user_messages}/{meta.assistant_messages}`"
    )
    lines.append(f"- Models: `{', '.join(sorted(models)) if models else '-'}`")
    lines.append("")

    if summaries:
        lines.append("## Claude Summaries")
        lines.append("")
        for item in summaries:
            lines.append(f"- {item}")
        lines.append("")

    lines.append("## Transcript Excerpt")
    lines.append("")
    for index, entry in enumerate(transcript, start=1):
        stamp = entry.timestamp.isoformat() if entry.timestamp else "-"
        lines.append(f"### {index}. {entry.role} ({stamp})")
        lines.append("```text")
        lines.append(entry.text)
        lines.append("```")
        lines.append("")

    return "\n".join(lines).strip() + "\n"


def export_conversation(args: argparse.Namespace) -> int:
    meta = select_conversation(args)
    transcript, summaries, models = build_transcript(
        meta.path,
        include_thinking=args.include_thinking,
    )

    if args.messages:
        transcript = transcript[-args.messages :]

    packet = format_resume_packet(meta, transcript, summaries, models)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(packet, encoding="utf-8")
        print(args.output)
        return 0

    print(packet, end="")
    return 0


def pick_conversation(args: argparse.Namespace) -> int:
    list_args = argparse.Namespace(
        projects_dir=args.projects_dir,
        cwd_contains=args.cwd_contains,
        limit=args.limit,
        json=False,
    )
    list_conversations(list_args)

    conversations = load_conversations(args.projects_dir, args.cwd_contains)
    if args.limit:
        conversations = conversations[: args.limit]
    if not conversations:
        return 1

    try:
        selected = input("Select conversation index: ").strip()
    except EOFError:
        raise ValueError("No conversation index provided.")

    if not selected.isdigit():
        raise ValueError(f"Invalid index: {selected}")

    export_args = argparse.Namespace(
        projects_dir=args.projects_dir,
        cwd_contains=args.cwd_contains,
        index=int(selected),
        session_id=None,
        file=None,
        messages=args.messages,
        include_thinking=args.include_thinking,
        output=args.output,
    )
    return export_conversation(export_args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Inspect Claude Code conversations stored in ~/.claude/projects and "
            "export a resume packet for Codex."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common_options(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument(
            "--projects-dir",
            type=Path,
            default=DEFAULT_PROJECTS_DIR,
            help="Claude projects directory (default: ~/.claude/projects)",
        )
        subparser.add_argument(
            "--cwd-contains",
            help="Optional case-insensitive filter on the conversation cwd path.",
        )

    list_parser = subparsers.add_parser("list", help="List conversations")
    add_common_options(list_parser)
    list_parser.add_argument("--limit", type=int, default=30, help="Maximum rows to show")
    list_parser.add_argument("--json", action="store_true", help="Output JSON")
    list_parser.set_defaults(handler=list_conversations)

    export_parser = subparsers.add_parser(
        "export", help="Export a conversation as a markdown resume packet"
    )
    add_common_options(export_parser)
    selector = export_parser.add_mutually_exclusive_group(required=True)
    selector.add_argument("--index", type=int, help="Conversation index from list output (1-based)")
    selector.add_argument("--session-id", help="Exact session ID")
    selector.add_argument("--file", type=Path, help="Exact path to a conversation jsonl file")
    export_parser.add_argument(
        "--messages",
        type=int,
        default=40,
        help="Number of latest user/assistant messages to include",
    )
    export_parser.add_argument(
        "--include-thinking",
        action="store_true",
        help="Include Claude thinking blocks when available",
    )
    export_parser.add_argument(
        "--output",
        type=Path,
        help="Write markdown packet to this path instead of stdout",
    )
    export_parser.set_defaults(handler=export_conversation)

    pick_parser = subparsers.add_parser(
        "pick",
        help="Interactively pick a conversation index and export a packet",
    )
    add_common_options(pick_parser)
    pick_parser.add_argument("--limit", type=int, default=30, help="Maximum rows to show")
    pick_parser.add_argument(
        "--messages",
        type=int,
        default=40,
        help="Number of latest user/assistant messages to include",
    )
    pick_parser.add_argument(
        "--include-thinking",
        action="store_true",
        help="Include Claude thinking blocks when available",
    )
    pick_parser.add_argument(
        "--output",
        type=Path,
        help="Write markdown packet to this path instead of stdout",
    )
    pick_parser.set_defaults(handler=pick_conversation)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        return args.handler(args)
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Aborted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
