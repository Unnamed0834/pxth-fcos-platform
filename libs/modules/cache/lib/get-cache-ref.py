#!/usr/bin/env python3
"""Get and validate the cache_ref from a node manifest.

Usage: python3 get-cache-ref.py --manifest <path>

Prints the cache_ref value (empty string if not present). An invalid or
path-traversing cache_ref is rejected rather than silently used as a path.
"""

import argparse
import json
import re
import sys

_SAFE_NODE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def main():
    parser = argparse.ArgumentParser(description="Get cache_ref from manifest")
    parser.add_argument("--manifest", required=True, help="Node manifest JSON")
    args = parser.parse_args()

    try:
        with open(args.manifest, encoding="utf-8") as handle:
            node_def = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"get-cache-ref: cannot read manifest: {exc}", file=sys.stderr)
        return 1

    ref = node_def.get("cache_ref", "")
    if not isinstance(ref, str):
        print("get-cache-ref: cache_ref must be a string", file=sys.stderr)
        return 1
    if ref and not _SAFE_NODE.match(ref):
        print(f"get-cache-ref: unsafe cache_ref rejected: {ref!r}", file=sys.stderr)
        return 1

    print(ref)
    return 0


if __name__ == "__main__":
    sys.exit(main())
