#!/usr/bin/env python3
"""List all known nodes from manifest files.

Usage: python3 list-nodes.py --apps-dir <path-to-apps-dir>
"""

import argparse
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="List all known nodes")
    parser.add_argument("--apps-dir", required=True, help="Path to apps directory")
    args = parser.parse_args()

    apps_path = Path(args.apps_dir)
    found = False

    for manifest_file in sorted(apps_path.glob("*/manifest.json")):
        found = True
        try:
            with open(manifest_file, encoding="utf-8") as handle:
                node_def = json.load(handle)
        except (OSError, ValueError) as exc:
            print(f"  {manifest_file.parent.name}  (unreadable: {exc})")
            continue
        node = node_def.get("node", manifest_file.parent.name)
        variants = list(node_def.get("variants", {}).keys())
        if variants:
            print(f"  {node}  (variants: {', '.join(variants)})")
        else:
            print(f"  {node}  ({node_def.get('version', '?')} manifest)")

    if not found:
        print("No nodes found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
