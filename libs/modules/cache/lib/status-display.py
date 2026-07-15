#!/usr/bin/env python3





import argparse
import json
import os
import sys
from datetime import datetime


def format_size(size_bytes):
    if size_bytes > 1048576:
        return f"{size_bytes // (1024*1024)}MB"
    elif size_bytes > 1024:
        return f"{size_bytes // 1024}KB"
    else:
        return f"{size_bytes}B"


def main():
    parser = argparse.ArgumentParser(description="Display cache status")
    parser.add_argument("--manifest", required=True, help="Cache manifest path")
    parser.add_argument("--ver-dir", required=True, help="Version directory")
    parser.add_argument("--node", required=True, help="Node name")
    args = parser.parse_args()

    if not os.path.isdir(args.ver_dir):
        print(f"Error: No cached artifacts for {args.node}", file=sys.stderr)
        sys.exit(1)


    current_version = "v1"
    print(f"Current version: {current_version}")


    if os.path.isdir(args.ver_dir):
        mtime = os.stat(args.ver_dir).st_mtime
        age_secs = int(datetime.now().timestamp() - mtime)
        age_hours = age_secs // 3600
        print(f"Age: {age_hours} hours")


    total_size = 0
    for root, dirs, files in os.walk(args.ver_dir):
        for f in files:
            fp = os.path.join(root, f)
            if os.path.isfile(fp) and f != ".cache-manifest.json":
                total_size += os.path.getsize(fp)
    if total_size > 1048576:
        size_str = f"{total_size // (1024*1024)}MB"
    elif total_size > 1024:
        size_str = f"{total_size // 1024}KB"
    else:
        size_str = f"{total_size}B"
    print(f"Total size: {size_str}")


    if os.path.isfile(args.manifest):
        with open(args.manifest) as f:
            state = json.load(f)
        print()
        print("Artifact breakdown:")
        for key, info in state.get("artifacts", {}).items():
            status = info["status"]
            size = info.get("size", 0)
            mark = "\u2713" if status == "ok" else "\u2717"
            print(f"  {mark} {key}: {status} ({format_size(size)})")


if __name__ == "__main__":
    main()
