#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path

DEV_APP_BUNDLE = "com.artisanalsoftware.PodHaven.dev"
PROD_APP_BUNDLE = "com.artisanalsoftware.PodHaven"
DEV_APP_GROUP = "group.podhaven.shared.dev"
PROD_APP_GROUP = "group.podhaven.shared"


@dataclass(frozen=True)
class LogCandidate:
    label: str
    path: Path
    exists: bool
    size_bytes: int | None
    modified_utc: str | None
    notes: str


def _simctl_container(bundle_id: str, container: str) -> Path | None:
    try:
        completed = subprocess.run(
            ["xcrun", "simctl", "get_app_container", "booted", bundle_id, container],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    text = completed.stdout.strip()
    return Path(text) if text else None


def _stat_candidate(label: str, path: Path, notes: str) -> LogCandidate:
    if path.exists():
        stat = path.stat()
        return LogCandidate(
            label=label,
            path=path,
            exists=True,
            size_bytes=stat.st_size,
            modified_utc=datetime.fromtimestamp(stat.st_mtime, tz=UTC).isoformat(),
            notes=notes,
        )
    return LogCandidate(
        label=label,
        path=path,
        exists=False,
        size_bytes=None,
        modified_utc=None,
        notes=notes,
    )


def app_log_candidates(*, variant: str) -> list[LogCandidate]:
    if variant not in {"dev", "release"}:
        raise ValueError(f"variant must be dev or release, got {variant!r}")

    candidates: list[LogCandidate] = []

    if variant == "dev":
        bundle = DEV_APP_BUNDLE
        subdir = "PodHavenDev"
        mac_container = Path.home() / "Library/Containers" / DEV_APP_BUNDLE / "Data"
    else:
        bundle = PROD_APP_BUNDLE
        subdir = None
        mac_container = Path.home() / "Library/Containers" / PROD_APP_BUNDLE / "Data"

    sim_data = _simctl_container(bundle, "data")
    if sim_data is not None:
        rel = f"Documents/{subdir}/log.ndjson" if subdir else "Documents/log.ndjson"
        candidates.append(
            _stat_candidate(
                "simulator (booted)",
                sim_data / rel,
                "Run `xcrun simctl get_app_container booted "
                f"{bundle} data`; Share sheet on Simulator does not reach the Mac.",
            )
        )
    else:
        candidates.append(
            LogCandidate(
                label="simulator (booted)",
                path=Path(f"<booted-sim>/{bundle}/Documents/.../log.ndjson"),
                exists=False,
                size_bytes=None,
                modified_utc=None,
                notes="No booted simulator or app not installed on it.",
            )
        )

    mac_rel = f"Documents/{subdir}/log.ndjson" if subdir else "Documents/log.ndjson"
    candidates.append(
        _stat_candidate(
            "my mac (Designed for iPhone)",
            mac_container / mac_rel,
            "Settings → Debug → Save on Mac; or copy from this host path.",
        )
    )

    return candidates


def widget_log_candidates(*, variant: str) -> list[LogCandidate]:
    if variant not in {"dev", "release"}:
        raise ValueError(f"variant must be dev or release, got {variant!r}")

    group = DEV_APP_GROUP if variant == "dev" else PROD_APP_GROUP
    bundle = DEV_APP_BUNDLE if variant == "dev" else PROD_APP_BUNDLE
    candidates: list[LogCandidate] = []

    sim_group = _simctl_container(bundle, group)
    if sim_group is not None:
        candidates.append(
            _stat_candidate(
                "simulator (booted) app group",
                sim_group / "widget-log.ndjson",
                f"Run `xcrun simctl get_app_container booted {bundle} {group}`.",
            )
        )
    else:
        candidates.append(
            LogCandidate(
                label="simulator (booted) app group",
                path=Path(f"<booted-sim>/{group}/widget-log.ndjson"),
                exists=False,
                size_bytes=None,
                modified_utc=None,
                notes="No booted simulator or app not installed on it.",
            )
        )

    candidates.append(
        _stat_candidate(
            "my mac app group",
            Path.home() / "Library/Group Containers" / group / "widget-log.ndjson",
            "Widget process; separate from app log.ndjson.",
        )
    )

    return candidates


def format_candidates(candidates: list[LogCandidate]) -> str:
    lines = [
        "Reference: where PodHaven NDJSON logs may live on this Mac host.",
        "Do not pick a path automatically — ask the user which run they reproduced and",
        "have them provide or confirm the path before analyzing.",
        "",
        "All Development/.dev builds on the same destination share one rolling file.",
        "Worktrees do not get separate log files.",
        "",
    ]
    for candidate in candidates:
        status = "missing"
        if candidate.exists:
            status = f"{candidate.size_bytes or 0:,} bytes, mtime {candidate.modified_utc}"
        lines.append(f"- {candidate.label}: {candidate.path}")
        lines.append(f"  {status}. {candidate.notes}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List known PodHaven NDJSON log paths (reference only; does not choose a file)."
    )
    parser.add_argument(
        "--widget",
        action="store_true",
        help="List widget-log.ndjson instead of log.ndjson.",
    )
    parser.add_argument(
        "--variant",
        choices=("dev", "release"),
        default="dev",
        help="Development (.dev) or production bundle paths. Default: dev.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    candidates = (
        widget_log_candidates(variant=args.variant)
        if args.widget
        else app_log_candidates(variant=args.variant)
    )

    if args.json:
        print(json.dumps({"candidates": [asdict(c) for c in candidates]}, indent=2, default=str))
        return 0

    print(format_candidates(candidates))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
