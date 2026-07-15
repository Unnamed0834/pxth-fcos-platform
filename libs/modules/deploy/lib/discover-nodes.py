#!/usr/bin/env python3






import argparse
import json
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Discover nodes from node-spec.json")
    parser.add_argument("--spec-path", required=True, help="Path to node-spec.json")
    args = parser.parse_args()

    spec_path = Path(args.spec_path)

    if not spec_path.is_file():

        print(spec_path.parent.name)
        return

    with open(spec_path) as f:
        spec = json.load(f)

    if "nodes" in spec and isinstance(spec["nodes"], list):
        for n in spec["nodes"]:
            print(n["name"])
    else:
        print(spec_path.parent.name)


if __name__ == "__main__":
    main()
