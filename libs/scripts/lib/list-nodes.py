#!/usr/bin/env python3





import argparse
import json
import os
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
        with open(manifest_file) as f:
            m = json.load(f)
        node = m.get("node", str(manifest_file.parent.name))
        variants = list(m.get("variants", {}).keys())
        if variants:
            print(f"  {node}  (variants: {', '.join(variants)})")
        else:
            print(f"  {node}  ({m.get('version', '?')} manifest)")

    if not found:
        print("No nodes found.")


if __name__ == "__main__":
    main()
