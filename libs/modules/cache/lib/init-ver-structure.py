#!/usr/bin/env python3





import json
import os
import sys


def main():
    manifest_file = os.environ.get("CACHE_MANIFEST_FILE", "")
    ver_dir = os.environ.get("VER_DIR", "")

    if not manifest_file or not ver_dir:
        print("Usage: CACHE_MANIFEST_FILE=<path> VER_DIR=<path> python3 init-ver-structure.py", file=sys.stderr)
        sys.exit(1)

    with open(manifest_file) as f:
        m = json.load(f)

    dirs = set()
    for a in m.get("artifacts", {}).values():
        dest = a.get("dest", "")
        if dest:
            d = os.path.dirname(dest)
            if d:
                dirs.add(d)

    for d in sorted(dirs):
        os.makedirs(os.path.join(ver_dir, d), exist_ok=True)


if __name__ == "__main__":
    main()
