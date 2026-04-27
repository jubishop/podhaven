#!/usr/bin/env python3
# Print the name of the newest available iPhone simulator (highest model number,
# preferring Pro Max > Pro > base) under the newest installed iOS runtime.
# Exits non-zero if no suitable device is found.

import json
import re
import subprocess
import sys


def runtime_version(key: str) -> tuple[int, int]:
    m = re.search(r"iOS-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def device_score(name: str) -> tuple[int, int] | None:
    m = re.match(r"iPhone (\d+)( Pro Max| Pro)?$", name)
    if not m:
        return None
    rank = {" Pro Max": 2, " Pro": 1, "": 0}[m.group(2) or ""]
    return (int(m.group(1)), rank)


def main() -> int:
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    data = json.loads(out)

    ios_runtimes = [r for r in data["devices"] if "iOS" in r and data["devices"][r]]
    if not ios_runtimes:
        print("No available iOS simulator runtimes found.", file=sys.stderr)
        return 1
    latest = max(ios_runtimes, key=runtime_version)

    candidates: list[tuple[tuple[int, int], str]] = []
    for d in data["devices"][latest]:
        score = device_score(d["name"])
        if score is not None:
            candidates.append((score, d["name"]))
    if not candidates:
        print(f"No iPhone devices under {latest}.", file=sys.stderr)
        return 1

    _, best = max(candidates, key=lambda t: t[0])
    print(best)
    return 0


if __name__ == "__main__":
    sys.exit(main())
