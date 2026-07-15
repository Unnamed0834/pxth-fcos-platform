#!/usr/bin/env python3
"""HMAC-SHA256 integrity sidecar for .cache-manifest.json.

The cache manifest is generated locally during `sync`. It records artifact
paths, sizes and hashes; if an attacker can edit both the manifest and the
files it describes, plain re-hashing is not enough (both can be forged).
A keyed HMAC, stored in a sidecar next to the manifest, detects that.

Key source, in priority order (no key => fail closed):
  1. $PXTH_CACHE_HMAC_KEY           (64 hex chars = 32-byte key)
  2. $PXTH_CACHE_HMAC_KEY_FILE      (file containing the hex key)
  3. /run/secrets/pxth-cache-hmac.env (PXTH_CACHE_HMAC_KEY=<hex>)

The key is supplied out-of-band by the operator (systemd credentials /
/etc/credstore). It is NEVER written into a bundle, a disk image, or this
repository. The sidecar contains only the digest, not the key.

Usage:
  python3 manifest_integrity.py sign   --manifest <path>
  python3 manifest_integrity.py verify --manifest <path>
"""

import argparse
import hashlib
import hmac
import json
import os
import re
import sys

DEFAULT_KEY_FILE = "/run/secrets/pxth-cache-hmac.env"
KEY_ENV = "PXTH_CACHE_HMAC_KEY"
KEY_FILE_ENV = "PXTH_CACHE_HMAC_KEY_FILE"
SIDECAR_SUFFIX = ".hmac"
DIGEST_PREFIX = "hmac_sha256="
_HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")


class IntegrityError(Exception):
    """Raised when the key or the integrity sidecar is unusable."""


def _read_env_file(path):
    """Parse KEY=value lines without executing shell code."""
    data = {}
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def load_key():
    """Load the 32-byte HMAC key from the environment / out-of-band store."""
    key_hex = os.environ.get(KEY_ENV, "").strip()

    if not key_hex:
        path = os.environ.get(KEY_FILE_ENV, "") or DEFAULT_KEY_FILE
        if path and os.path.isfile(path):
            try:
                key_hex = _read_env_file(path).get(KEY_ENV, "").strip()
            except OSError as exc:
                raise IntegrityError(f"cannot read HMAC key file {path}: {exc}") from exc

    if not key_hex:
        raise IntegrityError(
            "no cache HMAC key: set PXTH_CACHE_HMAC_KEY (64 hex chars) or "
            f"provision {DEFAULT_KEY_FILE} (systemd credentials)"
        )
    if not _HEX64.match(key_hex):
        raise IntegrityError(f"{KEY_ENV} must be exactly 64 hexadecimal characters")
    return bytes.fromhex(key_hex)


def canonical_bytes(obj):
    """Canonical JSON encoding so signing and verifying agree byte-for-byte."""
    return json.dumps(
        obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


def compute_digest(obj, key):
    return hmac.new(key, canonical_bytes(obj), hashlib.sha256).hexdigest()


def sidecar_path(manifest_path):
    return manifest_path + SIDECAR_SUFFIX


def sign(manifest_path, key=None):
    """Compute the HMAC over manifest_path and atomically write its sidecar."""
    selected_key = key if key is not None else load_key()
    with open(manifest_path, "r", encoding="utf-8") as handle:
        obj = json.load(handle)
    digest = compute_digest(obj, selected_key)

    sidecar = sidecar_path(manifest_path)
    temp = f"{sidecar}.tmp.{os.getpid()}"
    try:
        with open(temp, "w", encoding="utf-8") as handle:
            handle.write(f"{DIGEST_PREFIX}{digest}\n")
        os.chmod(temp, 0o600)
        os.replace(temp, sidecar)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return digest


def verify(manifest_path, key=None):
    """Verify the manifest against its sidecar. Raises IntegrityError on any problem."""
    selected_key = key if key is not None else load_key()

    sidecar = sidecar_path(manifest_path)
    if not os.path.isfile(sidecar):
        raise IntegrityError(f"missing integrity sidecar: {sidecar}")

    with open(sidecar, "r", encoding="utf-8") as handle:
        content = handle.read().strip()
    if not content.startswith(DIGEST_PREFIX):
        raise IntegrityError(f"malformed integrity sidecar: {sidecar}")
    recorded = content[len(DIGEST_PREFIX):].strip()
    if not _HEX64.match(recorded):
        raise IntegrityError(f"malformed HMAC value in {sidecar}")

    with open(manifest_path, "r", encoding="utf-8") as handle:
        obj = json.load(handle)
    actual = compute_digest(obj, selected_key)
    if not hmac.compare_digest(actual, recorded):
        raise IntegrityError(
            f"HMAC mismatch for {manifest_path}: cache manifest was modified after sync"
        )
    return True


def main():
    parser = argparse.ArgumentParser(description="Cache manifest HMAC integrity")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("sign", "verify"):
        child = sub.add_parser(name)
        child.add_argument("--manifest", required=True, help="Cache manifest path")
    args = parser.parse_args()

    try:
        if args.command == "sign":
            print(sign(args.manifest))
        else:
            verify(args.manifest)
            print("HMAC integrity: OK")
    except (IntegrityError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"HMAC integrity: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
