#!/usr/bin/env python3
"""Select a Cloud Run traffic-tag URL from a service JSON document."""

import json
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} TAG", file=sys.stderr)
        return 2

    try:
        service = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"invalid Cloud Run service JSON: {error}", file=sys.stderr)
        return 2

    requested_tag = sys.argv[1]
    traffic = service.get("status", {}).get("traffic", [])
    for target in traffic:
        if target.get("tag") == requested_tag and target.get("url"):
            print(target["url"])
            return 0

    print(f"Cloud Run traffic tag not found: {requested_tag}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
