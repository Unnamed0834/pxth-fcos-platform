#!/usr/bin/env python3
"""Verify the cache contract before packing an OEM disk.

Fail-closed checks:
  1. HMAC sidecar of .cache-manifest.json must be present and valid.
  2. Every expected artifact is RE-HASHED from disk (no image_digest shortcut).
  3. Signed artifacts must have sig_verified=true and a strong hash algorithm;
     unsigned artifacts must have a digest pinned in the declarative manifest.

Usage: python3 verify-contract.py --cache-manifest <path> --manifest <path>
                                  --ver-dir <path> [--inference-engine <name>]
"""

import argparse
import fnmatch
import hashlib
import json
import os
import re
import sys

import manifest_integrity

_HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")
_STRONG_ALGOS = ("sha256", "sha512")


def compute_sha256(filepath):
    digest = hashlib.sha256()
    with open(filepath, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_artifact_path(ver_dir, dest):
    if not dest or os.path.isabs(dest):
        return None
    parts = dest.replace("\\", "/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    return os.path.join(ver_dir, *parts)


def artifact_path(path):
    if os.path.isdir(path):
        for fname in sorted(os.listdir(path)):
            if fname.endswith(".tar"):
                return os.path.join(path, fname)
        return None
    return path


def normalize_digest(value):
    if not isinstance(value, str):
        return ""
    value = value.strip().lower()
    if value.startswith("sha256:"):
        value = value[len("sha256:"):]
    return value


def main():
    parser = argparse.ArgumentParser(description="Verify cache contract (fail-closed)")
    parser.add_argument("--cache-manifest", required=True, help="Cache manifest path")
    parser.add_argument("--manifest", required=True, help="Declarative pack manifest JSON")
    parser.add_argument("--ver-dir", required=True, help="Version directory")
    parser.add_argument("--inference-engine", default="", help="Override active container")
    args = parser.parse_args()

    try:
        manifest_integrity.verify(args.cache_manifest)
    except (manifest_integrity.IntegrityError, OSError, ValueError) as exc:
        print(f"  FAIL: cache manifest integrity: {exc}", file=sys.stderr)
        return 1

    with open(args.cache_manifest, encoding="utf-8") as handle:
        cache = json.load(handle)
    with open(args.manifest, encoding="utf-8") as handle:
        pack = json.load(handle)

    oem = pack.get("oem", {})
    bundle = oem.get("bundle", {})
    cache_artifacts = cache.get("artifacts", {})
    src_artifacts = pack.get("artifacts", {})

    expected = set()
    for pattern in bundle.get("sysext", []) + bundle.get("bin", []):
        for key, info in cache_artifacts.items():
            if fnmatch.fnmatch(info.get("dest", ""), pattern):
                expected.add(key)
    for key in bundle.get("containers", []):
        expected.add(key)
    active = args.inference_engine or oem.get("active", "")
    if active and active in cache_artifacts:
        expected.add(active)

    errors = 0
    for key in sorted(expected):
        if key not in cache_artifacts:
            print(f"  FAIL: {key} - not in cache manifest")
            errors += 1
            continue
        info = cache_artifacts[key]
        if info.get("status") != "ok":
            print(f"  FAIL: {key} - status={info.get('status')}")
            errors += 1
            continue

        full_path = resolve_artifact_path(args.ver_dir, info.get("dest", ""))
        if full_path is None:
            print(f"  FAIL: {key} - unsafe dest path")
            errors += 1
            continue
        full_path = artifact_path(full_path)
        if not full_path or not os.path.isfile(full_path):
            print(f"  FAIL: {key} - file missing from disk")
            errors += 1
            continue

        recorded = info.get("sha256", "")
        if not isinstance(recorded, str) or not _HEX64.match(recorded):
            print(f"  FAIL: {key} - missing/invalid recorded SHA256")
            errors += 1
            continue
        try:
            actual = compute_sha256(full_path)
        except OSError as exc:
            print(f"  FAIL: {key} - cannot read artifact: {exc}")
            errors += 1
            continue
        if actual != recorded.lower():
            print(f"  FAIL: {key} - SHA256 mismatch (re-hashed)")
            errors += 1
            continue

        if info.get("verified"):
            if info.get("sig_verified") is not True:
                print(f"  FAIL: {key} - signature not verified")
                errors += 1
                continue
            if str(info.get("hash_algo", "")).lower() not in _STRONG_ALGOS:
                print(f"  FAIL: {key} - weak hash algorithm")
                errors += 1
                continue
        else:
            image_digest = normalize_digest(info.get("image_digest", ""))
            pinned = normalize_digest(src_artifacts.get(key, {}).get("digest", ""))
            if not _HEX64.match(image_digest) or image_digest != pinned:
                print(f"  FAIL: {key} - unsigned artifact with no matching pinned digest")
                errors += 1
                continue

        print(f"  OK:   {key} ({info.get('size', 0)} bytes, SHA256 re-hashed)")

    print()
    print(f"Contract: {len(expected)} artifacts verified, {errors} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
