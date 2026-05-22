#!/usr/bin/env python3

"""Symbolicate MetricKit call stacks captured in PodHaven NDJSON logs.

PodHaven's MetricKitMonitor writes diagnostic payloads (crash, hang,
cpuException, diskWriteException, appLaunch) into log.ndjson as entries with a
`metricKitDiagnostic` metadata field. That field carries the raw
`MXDiagnosticPayload.jsonRepresentation()` JSON, which includes an
unsymbolicated MXCallStackTree: each frame has a `binaryUUID` and an
`offsetIntoBinaryTextSegment`, but no function/file/line.

Release-build binaries are stripped and the dSYM never ships to device, so
on-device symbolication is impossible. This script:

1. Locates MetricKit entries in the log.
2. Walks the call-stack tree, gathering (UUID, offset) frames.
3. Resolves each `binaryUUID` to a dSYM bundle via Sentry's Debug Files API
   (cached locally by UUID under ~/Library/Caches/podhaven-symbolicate).
4. Runs `atos` to resolve frames to function/file/line.
5. Prints a human-readable report (or JSON) alongside the diagnostic metadata.
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable, Iterable
from zoneinfo import ZoneInfo

PACIFIC = ZoneInfo("America/Los_Angeles")

METRICKIT_METADATA_KEY = "metricKitDiagnostic"
DEFAULT_CATEGORIES = ("crash", "hang", "cpuException", "diskWriteException", "appLaunch")
DEFAULT_CACHE_DIR = Path("~/Library/Caches/podhaven-symbolicate").expanduser()
DEFAULT_SENTRY_ORG = "artisanal-software"
DEFAULT_SENTRY_PROJECT = "podhaven"
SENTRY_API_BASE = "https://sentry.io/api/0"


def build_ssl_context() -> ssl.SSLContext:
    # python.org Python on macOS ships without a system trust store; certifi's
    # CA bundle is the standard fix and is usually already installed alongside
    # the interpreter. Fall back to the default context (which works under
    # /usr/bin/python3 and on Linux distros that wire the system store) when
    # certifi is missing.
    try:
        import certifi
    except ImportError:
        return ssl.create_default_context()
    return ssl.create_default_context(cafile=certifi.where())


@dataclass
class MetricKitEntry:
    line_number: int
    timestamp_ms: int
    category: str
    message: str
    payload: dict[str, Any]


@dataclass
class FrameRef:
    depth: int
    binary_uuid: str | None
    binary_name: str | None
    offset: int | None
    raw: dict[str, Any]
    symbol: str | None = None


@dataclass
class CallStack:
    index: int
    thread_attributed: bool
    per_thread: bool
    frames: list[FrameRef]


@dataclass
class SymbolicatedEntry:
    entry: MetricKitEntry
    architecture: str | None
    diagnostic_meta: dict[str, Any]
    call_stacks: list[CallStack]
    missing_uuids: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def format_timestamp(timestamp_ms: int) -> str:
    dt = datetime.fromtimestamp(timestamp_ms / 1000, UTC).astimezone(PACIFIC)
    millis = int(timestamp_ms % 1000)
    return f"{dt:%Y-%m-%d %H:%M:%S}.{millis:03d} {dt.tzname()}"


def categorize_entry(entry: dict[str, Any]) -> str | None:
    """Infer the MetricKit category from the log entry's message."""
    message = entry.get("message", "")
    if not message.startswith("MetricKit "):
        return None
    rest = message[len("MetricKit ") :]
    return rest.split(" ", 1)[0] if rest else None


def iter_metrickit_entries(path: Path) -> Iterable[MetricKitEntry]:
    """Yield MetricKit entries found in the NDJSON log."""
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            stripped = raw.strip()
            if not stripped:
                continue
            try:
                entry = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            metadata = entry.get("metadata") or {}
            blob = metadata.get(METRICKIT_METADATA_KEY)
            if not isinstance(blob, str):
                continue
            try:
                payload = json.loads(blob)
            except json.JSONDecodeError:
                continue
            category = categorize_entry(entry) or "unknown"
            yield MetricKitEntry(
                line_number=line_number,
                timestamp_ms=int(entry.get("timestamp", 0)),
                category=category,
                message=str(entry.get("message", "")),
                payload=payload,
            )


def flatten_frames(root_frames: list[dict[str, Any]] | None, depth: int = 0) -> list[FrameRef]:
    flat: list[FrameRef] = []
    for raw in root_frames or []:
        binary_uuid = raw.get("binaryUUID")
        offset_raw = raw.get("offsetIntoBinaryTextSegment")
        offset = int(offset_raw) if isinstance(offset_raw, (int, float, str)) and str(offset_raw).lstrip("-").isdigit() else None
        flat.append(
            FrameRef(
                depth=depth,
                binary_uuid=binary_uuid if isinstance(binary_uuid, str) else None,
                binary_name=raw.get("binaryName") if isinstance(raw.get("binaryName"), str) else None,
                offset=offset,
                raw=raw,
            )
        )
        flat.extend(flatten_frames(raw.get("subFrames"), depth + 1))
    return flat


def extract_call_stacks(payload: dict[str, Any]) -> list[CallStack]:
    tree = payload.get("callStackTree") or {}
    stacks_raw = tree.get("callStacks") or []
    stacks: list[CallStack] = []
    for index, raw in enumerate(stacks_raw):
        frames = flatten_frames(raw.get("callStackRootFrames"))
        stacks.append(
            CallStack(
                index=index,
                thread_attributed=bool(raw.get("threadAttributed", False)),
                per_thread=bool(raw.get("callStackPerThread", False)),
                frames=frames,
            )
        )
    return stacks


def diagnostic_metadata(payload: dict[str, Any]) -> dict[str, Any]:
    meta = payload.get("diagnosticMetaData")
    return meta if isinstance(meta, dict) else {}


def normalize_uuid(value: str) -> str:
    """Normalize a binary UUID to Sentry's debug-id format (lowercase with hyphens)."""
    return value.strip().lower()


def load_sentry_config(args: argparse.Namespace) -> tuple[str | None, str, str]:
    token = args.sentry_token or os.environ.get("SENTRY_AUTH_TOKEN")
    org = args.sentry_org
    project = args.sentry_project

    config_path = Path("~/.sentryclirc").expanduser()
    if (token is None or args.sentry_org == DEFAULT_SENTRY_ORG) and config_path.exists():
        parser = configparser.ConfigParser()
        try:
            parser.read(config_path)
        except configparser.Error:
            parser = None
        if parser is not None:
            if token is None and parser.has_option("auth", "token"):
                token = parser.get("auth", "token")
            if args.sentry_org == DEFAULT_SENTRY_ORG and parser.has_option("defaults", "org"):
                org = parser.get("defaults", "org")
            if args.sentry_project == DEFAULT_SENTRY_PROJECT and parser.has_option("defaults", "project"):
                project = parser.get("defaults", "project")

    return token, org, project


class DSYMResolver:
    """Resolve `binaryUUID -> path to inner DWARF file`, with on-disk cache."""

    def __init__(
        self,
        cache_dir: Path,
        sentry_token: str | None,
        sentry_org: str,
        sentry_project: str,
        offline: bool,
        verbose: bool = False,
        opener: Callable[[urllib.request.Request], Any] | None = None,
    ) -> None:
        self.cache_dir = cache_dir
        self.sentry_token = sentry_token
        self.sentry_org = sentry_org
        self.sentry_project = sentry_project
        self.offline = offline
        self.verbose = verbose
        self._ssl_context = build_ssl_context()
        self._opener = opener or self._default_opener
        self._misses: set[str] = set()
        cache_dir.mkdir(parents=True, exist_ok=True)

    def _default_opener(self, request: urllib.request.Request) -> Any:
        return urllib.request.urlopen(request, context=self._ssl_context)

    def resolve(self, uuid: str) -> Path | None:
        key = normalize_uuid(uuid)
        cached = self._lookup_cache(key)
        if cached is not None:
            return cached
        if self.offline:
            self._misses.add(key)
            return None
        if not self.sentry_token:
            self._misses.add(key)
            self._log(f"no Sentry token configured; cannot fetch dSYM for {key}")
            return None
        try:
            return self._download_and_cache(key)
        except Exception as exc:
            self._misses.add(key)
            self._log(f"dSYM fetch failed for {key}: {exc}")
            return None

    @property
    def misses(self) -> list[str]:
        return sorted(self._misses)

    def _log(self, message: str) -> None:
        if self.verbose:
            print(f"[symbolicate] {message}", file=sys.stderr)

    def _entry_dir(self, key: str) -> Path:
        return self.cache_dir / key

    def _lookup_cache(self, key: str) -> Path | None:
        entry_dir = self._entry_dir(key)
        if not entry_dir.is_dir():
            return None
        dwarf = self._find_dwarf(entry_dir)
        return dwarf

    @staticmethod
    def _is_macho(path: Path) -> bool:
        # Mach-O magic numbers (32/64-bit, both endianness, plus fat archive).
        magics = {
            b"\xca\xfe\xba\xbe",  # fat
            b"\xfe\xed\xfa\xce",  # MH_MAGIC
            b"\xfe\xed\xfa\xcf",  # MH_MAGIC_64
            b"\xce\xfa\xed\xfe",  # MH_CIGAM
            b"\xcf\xfa\xed\xfe",  # MH_CIGAM_64
        }
        try:
            with path.open("rb") as f:
                return f.read(4) in magics
        except OSError:
            return False

    @classmethod
    def _find_dwarf(cls, root: Path) -> Path | None:
        # Standard dSYM bundle layout (zipped responses).
        for candidate in root.rglob("Contents/Resources/DWARF/*"):
            if candidate.is_file():
                return candidate
        for candidate in root.rglob("*.dSYM"):
            inner = candidate / "Contents" / "Resources" / "DWARF"
            if inner.is_dir():
                children = [child for child in inner.iterdir() if child.is_file()]
                if children:
                    return children[0]
        for candidate in root.rglob("*"):
            if candidate.is_file() and candidate.parent.name == "DWARF":
                return candidate
        # Sentry's debug-files download endpoint returns the raw Mach-O with
        # debug info directly (Content-Type: application/x-mach-binary), not a
        # zipped dSYM bundle. Accept any Mach-O file at the cache root.
        for candidate in sorted(root.iterdir()) if root.is_dir() else []:
            if candidate.is_file() and cls._is_macho(candidate):
                return candidate
        return None

    def _download_and_cache(self, key: str) -> Path | None:
        files = self._list_debug_files(key)
        if not files:
            self._log(f"Sentry returned no debug files for {key}")
            self._misses.add(key)
            return None
        target_dir = self._entry_dir(key)
        target_dir.mkdir(parents=True, exist_ok=True)
        for record in files:
            file_id = record.get("id")
            if not isinstance(file_id, str):
                continue
            try:
                self._download_file(file_id, target_dir)
            except Exception as exc:
                self._log(f"download {file_id} failed: {exc}")
                continue
            dwarf = self._find_dwarf(target_dir)
            if dwarf is not None:
                self._log(f"cached dSYM for {key} at {dwarf}")
                return dwarf
        return None

    def _list_debug_files(self, debug_id: str) -> list[dict[str, Any]]:
        path = f"projects/{self.sentry_org}/{self.sentry_project}/files/dsyms/"
        query = urllib.parse.urlencode({"debug_id": debug_id})
        url = f"{SENTRY_API_BASE}/{path}?{query}"
        req = urllib.request.Request(url, headers=self._auth_headers())
        with self._opener(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if not isinstance(data, list):
            return []
        return data

    def _download_file(self, file_id: str, target_dir: Path) -> None:
        path = f"projects/{self.sentry_org}/{self.sentry_project}/files/dsyms/"
        query = urllib.parse.urlencode({"id": file_id})
        url = f"{SENTRY_API_BASE}/{path}?{query}"
        req = urllib.request.Request(url, headers=self._auth_headers())
        with self._opener(req) as resp:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
                shutil.copyfileobj(resp, tmp)
                tmp_path = Path(tmp.name)
        try:
            if zipfile.is_zipfile(tmp_path):
                with zipfile.ZipFile(tmp_path) as archive:
                    archive.extractall(target_dir)
            else:
                # Sentry's debug-files endpoint returns the raw Mach-O with
                # debug info. Save it under a stable filename so atos can
                # locate it by walking the cache dir.
                shutil.move(tmp_path, target_dir / f"{file_id}.macho")
        finally:
            if tmp_path.exists():
                tmp_path.unlink()

    def _auth_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.sentry_token}", "Accept": "application/json"}


def run_atos(binary_path: Path, arch: str | None, offsets: list[int]) -> list[str | None]:
    """Resolve a batch of text-segment offsets to symbols via atos.

    MetricKit's `offsetIntoBinaryTextSegment` is the offset from the start of
    the binary image, not a virtual memory address. The `-offset` flag tells
    atos to interpret each input the same way, which is the standard recipe
    for symbolicating MetricKit and crash-report frames against a dSYM or
    debug-info Mach-O.
    """
    if not offsets:
        return []
    args = ["atos", "-o", str(binary_path), "-offset"]
    if arch:
        args += ["-arch", arch]
    # Bare numeric inputs to atos are interpreted as hex; we always pass
    # the offset with a `0x` prefix so an unprefixed decimal `1689452`
    # isn't silently mis-read as `0x1689452`.
    args += [f"0x{int(o):x}" for o in offsets]
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return [None] * len(offsets)
    return parse_atos_output(proc.stdout, expected=len(offsets))


def parse_atos_output(stdout: str, expected: int) -> list[str | None]:
    lines = [line for line in stdout.splitlines() if line.strip()]
    if len(lines) >= expected:
        return [line.strip() for line in lines[:expected]]
    padded: list[str | None] = [line.strip() for line in lines]
    padded.extend([None] * (expected - len(padded)))
    return padded


def group_frames_by_uuid(stacks: list[CallStack]) -> dict[str, list[FrameRef]]:
    grouped: dict[str, list[FrameRef]] = defaultdict(list)
    for stack in stacks:
        for frame in stack.frames:
            if frame.binary_uuid is None or frame.offset is None:
                continue
            grouped[normalize_uuid(frame.binary_uuid)].append(frame)
    return grouped


def symbolicate_entry(
    entry: MetricKitEntry,
    resolver: DSYMResolver | None,
) -> SymbolicatedEntry:
    meta = diagnostic_metadata(entry.payload)
    arch_raw = meta.get("platformArchitecture")
    arch = arch_raw if isinstance(arch_raw, str) else None
    stacks = extract_call_stacks(entry.payload)
    grouped = group_frames_by_uuid(stacks)
    missing: list[str] = []
    notes: list[str] = []

    if resolver is None:
        for uuid in grouped:
            missing.append(uuid)
        notes.append("symbolication skipped (no resolver)")
        return SymbolicatedEntry(
            entry=entry,
            architecture=arch,
            diagnostic_meta=meta,
            call_stacks=stacks,
            missing_uuids=missing,
            notes=notes,
        )

    for uuid, frames in grouped.items():
        dwarf = resolver.resolve(uuid)
        if dwarf is None:
            missing.append(uuid)
            continue
        offsets = [frame.offset for frame in frames if frame.offset is not None]
        symbols = run_atos(dwarf, arch, offsets)
        for frame, symbol in zip(frames, symbols):
            frame.symbol = symbol

    return SymbolicatedEntry(
        entry=entry,
        architecture=arch,
        diagnostic_meta=meta,
        call_stacks=stacks,
        missing_uuids=missing,
        notes=notes,
    )


def render_entry_text(symbolicated: SymbolicatedEntry) -> str:
    entry = symbolicated.entry
    lines: list[str] = []
    lines.append(
        f"## {entry.category} diagnostic — {format_timestamp(entry.timestamp_ms)} "
        f"(line {entry.line_number})"
    )
    lines.append(f"Message: {entry.message}")
    if symbolicated.architecture:
        lines.append(f"Architecture: {symbolicated.architecture}")

    meta_summary = render_diagnostic_meta(symbolicated.diagnostic_meta)
    if meta_summary:
        lines.append("Diagnostic metadata:")
        for key, value in meta_summary:
            lines.append(f"  {key}: {value}")

    if symbolicated.missing_uuids:
        lines.append(
            "Unresolved binaries (no dSYM available): "
            + ", ".join(symbolicated.missing_uuids)
        )
    if symbolicated.notes:
        for note in symbolicated.notes:
            lines.append(f"Note: {note}")

    if not symbolicated.call_stacks:
        lines.append("No call stacks present in payload.")
        return "\n".join(lines)

    for stack in symbolicated.call_stacks:
        marker = "thread-attributed" if stack.thread_attributed else "thread-unspecified"
        lines.append(f"Stack {stack.index} ({marker}, perThread={stack.per_thread}):")
        if not stack.frames:
            lines.append("  <empty>")
            continue
        for frame in stack.frames:
            indent = "  " + ("  " * frame.depth)
            binary = frame.binary_name or "?"
            offset = f"+{frame.offset}" if frame.offset is not None else ""
            symbol = frame.symbol or "<unresolved>"
            lines.append(f"{indent}{binary}{offset}  {symbol}")
    return "\n".join(lines)


def render_diagnostic_meta(meta: dict[str, Any]) -> list[tuple[str, str]]:
    interesting_keys = [
        "platformArchitecture",
        "applicationBuildVersion",
        "appBuildVersion",
        "appVersion",
        "osVersion",
        "regionFormat",
        "deviceType",
        "bundleIdentifier",
        "exceptionType",
        "exceptionCode",
        "signal",
        "terminationReason",
        "virtualMemoryRegionInfo",
        "hangDuration",
        "diagnosticVersion",
        "writesCaused",
    ]
    pairs: list[tuple[str, str]] = []
    for key in interesting_keys:
        if key in meta:
            pairs.append((key, str(meta[key])))
    return pairs


def serialize_frame(frame: FrameRef) -> dict[str, Any]:
    return {
        "depth": frame.depth,
        "binaryUUID": frame.binary_uuid,
        "binaryName": frame.binary_name,
        "offsetIntoBinaryTextSegment": frame.offset,
        "symbol": frame.symbol,
    }


def serialize_entry(symbolicated: SymbolicatedEntry) -> dict[str, Any]:
    entry = symbolicated.entry
    return {
        "line_number": entry.line_number,
        "timestamp_ms": entry.timestamp_ms,
        "timestamp_pt": format_timestamp(entry.timestamp_ms),
        "category": entry.category,
        "message": entry.message,
        "architecture": symbolicated.architecture,
        "diagnosticMetaData": symbolicated.diagnostic_meta,
        "missing_uuids": symbolicated.missing_uuids,
        "notes": symbolicated.notes,
        "callStacks": [
            {
                "index": stack.index,
                "threadAttributed": stack.thread_attributed,
                "callStackPerThread": stack.per_thread,
                "frames": [serialize_frame(frame) for frame in stack.frames],
            }
            for stack in symbolicated.call_stacks
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Symbolicate MetricKit call stacks captured in PodHaven NDJSON logs."
    )
    parser.add_argument("path", help="Path to log.ndjson or widget-log.ndjson.")
    parser.add_argument(
        "--around",
        type=int,
        help="Restrict to MetricKit entries within --window-ms of this epoch-ms timestamp.",
    )
    parser.add_argument(
        "--window-ms",
        type=int,
        default=300000,
        help="Window size in milliseconds for --around. Default: 300000.",
    )
    parser.add_argument(
        "--category",
        action="append",
        choices=list(DEFAULT_CATEGORIES) + ["unknown"],
        help="Restrict to MetricKit categories. Repeatable; default is all.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Maximum number of MetricKit entries to symbolicate. Default: 10.",
    )
    parser.add_argument(
        "--cache-dir",
        default=str(DEFAULT_CACHE_DIR),
        help=f"dSYM cache directory. Default: {DEFAULT_CACHE_DIR}.",
    )
    parser.add_argument(
        "--sentry-org",
        default=DEFAULT_SENTRY_ORG,
        help=f"Sentry organization slug. Default: {DEFAULT_SENTRY_ORG} "
        "(overridden by ~/.sentryclirc [defaults] org=).",
    )
    parser.add_argument(
        "--sentry-project",
        default=DEFAULT_SENTRY_PROJECT,
        help=f"Sentry project slug. Default: {DEFAULT_SENTRY_PROJECT} "
        "(overridden by ~/.sentryclirc [defaults] project=).",
    )
    parser.add_argument(
        "--sentry-token",
        help="Sentry auth token. Falls back to SENTRY_AUTH_TOKEN or ~/.sentryclirc.",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="Do not contact Sentry; only use dSYMs already in the cache.",
    )
    parser.add_argument(
        "--json",
        dest="json_output",
        action="store_true",
        help="Emit machine-readable JSON instead of text.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Emit progress logs to stderr while fetching dSYMs.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = Path(args.path).expanduser()
    if not path.exists():
        print(f"Log file not found: {path}", file=sys.stderr)
        return 1

    selected_categories = set(args.category) if args.category else set(DEFAULT_CATEGORIES) | {"unknown"}

    entries: list[MetricKitEntry] = []
    for entry in iter_metrickit_entries(path):
        if entry.category not in selected_categories:
            continue
        if args.around is not None and abs(entry.timestamp_ms - args.around) > args.window_ms:
            continue
        entries.append(entry)
        if len(entries) >= args.limit:
            break

    token, org, project = load_sentry_config(args)
    resolver = DSYMResolver(
        cache_dir=Path(args.cache_dir).expanduser(),
        sentry_token=token,
        sentry_org=org,
        sentry_project=project,
        offline=args.offline,
        verbose=args.verbose,
    )

    if not entries:
        if args.json_output:
            print(json.dumps({"file": str(path), "entries": []}, indent=2))
        else:
            print(f"No MetricKit entries found in {path}.")
        return 0

    symbolicated = [symbolicate_entry(entry, resolver) for entry in entries]

    if args.json_output:
        payload = {
            "file": str(path),
            "sentry": {"org": org, "project": project, "offline": args.offline},
            "missing_uuids": sorted({uuid for s in symbolicated for uuid in s.missing_uuids}),
            "entries": [serialize_entry(s) for s in symbolicated],
        }
        print(json.dumps(payload, indent=2))
        return 0

    print(f"File: {path}")
    print(f"MetricKit entries: {len(entries)}")
    print(f"Sentry: org={org} project={project} offline={args.offline}")
    print()
    for s in symbolicated:
        print(render_entry_text(s))
        print()
    if resolver.misses:
        print("Binaries with no resolvable dSYM:")
        for uuid in resolver.misses:
            print(f"  {uuid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
