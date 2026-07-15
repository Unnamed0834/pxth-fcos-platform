#!/usr/bin/env python3
"""Write/merge OEM tarball metadata with strictly validated argv inputs.

Replaces string-interpolated `python3 -c` snippets in pack/engine.sh.

Usage:
  oem_metadata.py write    --node NAME --sha256 HEX --size INT --output PATH
  oem_metadata.py add      --accum PATH --node NAME --sha256 HEX --size INT
  oem_metadata.py finalize --accum PATH --output PATH
"""

import argparse
import json
import os
import re
import sys
import tempfile

_HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")
_SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def _validate(node, sha256, size):
    if not _SAFE_NAME.match(node):
        raise ValueError(f"unsafe node name: {node!r}")
    if not _HEX64.match(sha256):
        raise ValueError(f"invalid sha256: {sha256!r}")
    try:
        size = int(size)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"invalid size: {size!r}") from exc
    if size < 0:
        raise ValueError("size must be non-negative")
    return {"oem_disk_sha256": sha256.lower(), "tarball_size": size}


def _atomic_write_json(path, obj):
    directory = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".oem-metadata.", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(obj, handle, indent=2)
            handle.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def _read_json(path, default=None):
    if not os.path.isfile(path):
        return {} if default is None else default
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return data


def main():
    parser = argparse.ArgumentParser(description="OEM metadata writer")
    sub = parser.add_subparsers(dest="command", required=True)

    p_write = sub.add_parser("write")
    p_write.add_argument("--node", required=True)
    p_write.add_argument("--sha256", required=True)
    p_write.add_argument("--size", required=True)
    p_write.add_argument("--output", required=True)

    p_add = sub.add_parser("add")
    p_add.add_argument("--accum", required=True)
    p_add.add_argument("--node", required=True)
    p_add.add_argument("--sha256", required=True)
    p_add.add_argument("--size", required=True)

    p_final = sub.add_parser("finalize")
    p_final.add_argument("--accum", required=True)
    p_final.add_argument("--output", required=True)

    args = parser.parse_args()

    try:
        if args.command == "write":
            _atomic_write_json(
                args.output, _validate(args.node, args.sha256, args.size)
            )
        elif args.command == "add":
            data = _read_json(args.accum)
            data[args.node] = _validate(args.node, args.sha256, args.size)
            _atomic_write_json(args.accum, data)
        else:
            data = _read_json(args.accum)
            _atomic_write_json(args.output, data)
    except (ValueError, OSError) as exc:
        print(f"oem_metadata: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
