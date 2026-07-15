#!/usr/bin/env python3







import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Parse a single JSON field")
    parser.add_argument("--file", default="", help="JSON file path (empty = stdin)")
    parser.add_argument("--field", required=True, help="Field name to extract")
    args = parser.parse_args()

    if args.file:
        with open(args.file) as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)


    field = args.field
    for part in field.split("."):
        if isinstance(data, dict):
            data = data.get(part, "")
        else:
            data = ""
            break

    print(data if data != "" else "")


if __name__ == "__main__":
    main()
