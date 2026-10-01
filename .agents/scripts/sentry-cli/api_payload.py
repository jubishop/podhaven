#!/usr/bin/env python3

"""Validate a sentry api --json response and emit only its endpoint payload."""

import json
import re
import sys


def payload(response, kind):
    if not isinstance(response, dict):
        raise ValueError("expected a Sentry API response envelope")
    status = response.get("status")
    if type(status) is not int:
        raise ValueError("expected an integer HTTP status in the response envelope")
    if not 200 <= status < 300:
        raise ValueError(f"Sentry API returned HTTP {status}")
    if "body" not in response:
        raise ValueError("expected body in the response envelope")
    body = response["body"]
    rows = body
    if kind == "activity":
        if not isinstance(body, dict) or "activity" not in body:
            raise ValueError("expected an object with an activity list")
        rows = body["activity"]
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise ValueError(f"expected a list of objects for {kind}")
    for row in rows:
        if kind == "tags":
            if not isinstance(row.get("value"), str) or type(row.get("count")) is not int:
                raise ValueError("expected tag value (string) and count (integer)")
        elif kind == "attachments":
            if (not isinstance(row.get("id"), (str, int)) or isinstance(row["id"], bool)
                    or not str(row["id"]) or not isinstance(row.get("name"), str)):
                raise ValueError("expected attachment id and name")
        elif kind == "events":
            if not isinstance(row.get("id"), str) or not re.fullmatch(r"[A-Za-z0-9_-]+", row["id"]):
                raise ValueError("expected a safe event ID")
    return body


def main():
    endpoint, kind = sys.argv[1:]
    try:
        response = json.load(sys.stdin)
        body = payload(response, kind)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print(f"Error: {endpoint}: invalid JSON in Sentry API response", file=sys.stderr)
        return 1
    except ValueError as error:
        print(f"Error: {endpoint}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(body, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
