#!/usr/bin/env python3
"""resolve-variables.py - Auto-discover and resolve variables from shared/ and <node>/ directories.

Walks variables/shared/ then variables/<node>/, reads all .yml, flattens to JSON.
Node-specific values override shared values on key collision.
Outputs JSON to stdout for consumption by pxth-deploy.

Environment variables:
    VARS_DIR  - Path to variables/ root (defaults to variables/)
    NODE      - Node name for node-specific variable lookup
"""

import json
import os
import sys

import yaml


def flatten_keys(data, prefix="", result=None):
    """Flatten nested dict to dot-notation keys."""
    if result is None:
        result = {}
    for k, v in data.items():
        full_key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            flatten_keys(v, full_key, result)
        else:
            result[full_key] = str(v) if not isinstance(v, str) else v
    return result


def walk_dir(directory, result):
    """Walk a variables directory and flatten all YAML files."""
    if not os.path.isdir(directory):
        return
    for item in sorted(os.listdir(directory)):
        item_path = os.path.join(directory, item)
        if os.path.isfile(item_path) and item.endswith((".yml", ".yaml")):
            with open(item_path) as f:
                data = yaml.safe_load(f)
            if data:
                flatten_keys(data, result=result)
        elif os.path.isdir(item_path):
            for fname in sorted(os.listdir(item_path)):
                if not fname.endswith((".yml", ".yaml")):
                    continue
                fpath = os.path.join(item_path, fname)
                with open(fpath) as f:
                    data = yaml.safe_load(f)
                if data:
                    flatten_keys(data, result=result)


def main():
    vars_dir = os.environ.get("VARS_DIR", "variables")
    node = os.environ.get("NODE", "")

    result = {}

    walk_dir(os.path.join(vars_dir, "shared"), result)
    if node:
        walk_dir(os.path.join(vars_dir, node), result)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
