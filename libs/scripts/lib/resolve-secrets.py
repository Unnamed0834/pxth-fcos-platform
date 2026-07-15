#!/usr/bin/env python3
"""resolve-secrets.py - Auto-discover and resolve secrets.

Walks secrets/shared/ and secrets/<app>/shared/, decrypts .yml via SOPS,
flattens to JSON. Outputs JSON to stdout for consumption by pxth-deploy.

Environment variables:
    SECRETS_DIR  - Path to secrets/ root (defaults to secrets/)
    SOPS_AGE_KEY_FILE - Path to SOPS age key
    APP_NAME    - App name for multi-node support (e.g., "node-r")
"""

import json
import os
import subprocess
import sys

import yaml


def flatten_keys(data, prefix="", result=None):
    """Flatten nested dict to underscore-notation keys."""
    if result is None:
        result = {}
    for k, v in data.items():
        full_key = f"{prefix}_{k}" if prefix else k
        if isinstance(v, dict):
            flatten_keys(v, full_key, result)
        else:
            result[full_key] = str(v) if not isinstance(v, str) else v
    return result


def walk_dir(directory, result, blacklist=None):
    """Walk a secrets directory and flatten all YAML files."""
    if not os.path.isdir(directory):
        return result
    if blacklist is None:
        blacklist = set()
    for category in sorted(os.listdir(directory)):
        cat_path = os.path.join(directory, category)
        if category in blacklist:
            continue
        if not os.path.isdir(cat_path):
            continue
        for fname in sorted(os.listdir(cat_path)):
            if not fname.endswith((".yml", ".yaml")):
                continue
            fpath = os.path.join(cat_path, fname)
            proc = subprocess.run(
                ["sops", "-d", fpath],
                capture_output=True,
                env={**os.environ, "SOPS_AGE_KEY_FILE": os.environ["SOPS_AGE_KEY_FILE"]},
                timeout=30,
            )
            if proc.returncode != 0:
                with open(fpath) as f:
                    data = yaml.safe_load(f)
            else:
                data = yaml.safe_load(proc.stdout)
            if data:
                flatten_keys(data, result=result)
    return result


def main():
    secrets_dir = os.environ.get("SECRETS_DIR", "secrets")
    age_key = os.environ.get("SOPS_AGE_KEY_FILE", "")
    app_name = os.environ.get("APP_NAME", "")

    if not age_key:
        print("ERROR: SOPS_AGE_KEY_FILE not set", file=sys.stderr)
        sys.exit(1)

    result = {}

    result = walk_dir(os.path.join(secrets_dir, "shared"), result)

    if app_name:
        result = walk_dir(os.path.join(secrets_dir, app_name, "shared"), result, blacklist={"tofu"})
    print(json.dumps(result))


if __name__ == "__main__":
    main()
