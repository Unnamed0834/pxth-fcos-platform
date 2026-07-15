#!/usr/bin/env python3
"""List subnode names from a node-spec.json (safe argv-based helper).

Usage: python3 list_subnodes.py --spec <path>
"""

import argparse
import json
import re
import sys

_SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def main():
    parser = argparse.ArgumentParser(description="List subnodes from node-spec.json")
    parser.add_argument("--spec", required=True, help="Path to node-spec.json")
    args = parser.parse_args()

    try:
        with open(args.spec, encoding="utf-8") as handle:
            spec = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"list_subnodes: cannot read spec: {exc}", file=sys.stderr)
        return 1

    nodes = spec.get("nodes", [])
    if not isinstance(nodes, list):
        return 0

    for entry in nodes:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name_us") or entry.get("name", "")
        if not isinstance(name, str) or not _SAFE_NAME.match(name):
            print(f"list_subnodes: unsafe subnode name rejected: {name!r}", file=sys.stderr)
            return 1
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
