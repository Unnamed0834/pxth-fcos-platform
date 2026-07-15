#!/usr/bin/env python3
"""Verify cached artifacts against the cache state record.

Fail-closed contract:
  1. The .cache-manifest.json HMAC sidecar must be present and valid.
  2. Every artifact is re-hashed from disk on EVERY verification. No recorded
     digest is ever trusted as proof of file integrity (no image_digest shortcut).
  3. A signed artifact must carry sig_verified=true and a SHA256/SHA512 hash.
  4. Unsigned artifacts must have a digest pinned in the declarative manifest.
  5. Any failure exits non-zero.

Usage: python3 verify-cache.py --manifest <cache-manifest.json>
                               --ver-dir <path> --source-manifest <manifest.json>
"""

import argparse
import hashlib
import json
import os
import re
import sys

import manifest_integrity

_HEX = {64: re.compile(r"^[0-9a-fA-F]{64}$"), 128: re.compile(r"^[0-9a-fA-F]{128}$")}
_STRONG_ALGOS = ("sha256", "sha512")


def compute_hash(filepath, algo="sha256"):
    digest = hashlib.new(algo)
    with open(filepath, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_artifact_path(ver_dir, dest):
    """Join dest under ver_dir, refusing absolute paths and '..' traversal."""
    if not dest or os.path.isabs(dest):
        return None
    parts = dest.replace("\\", "/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    return os.path.join(ver_dir, *parts)


def artifact_path(art_path):
    """Directories resolve to their first .tar member (build outputs)."""
    if os.path.isdir(art_path):
        for fname in sorted(os.listdir(art_path)):
            if fname.endswith(".tar"):
                return os.path.join(art_path, fname)
        return None
    return art_path


def normalize_digest(value):
    if not isinstance(value, str):
        return ""
    value = value.strip().lower()
    if value.startswith("sha256:"):
        value = value[len("sha256:"):]
    return value


def main():
    parser = argparse.ArgumentParser(description="Verify cached artifacts (fail-closed)")
    parser.add_argument("--manifest", required=True, help="Cache manifest path")
    parser.add_argument("--ver-dir", required=True, help="Version directory")
    parser.add_argument("--source-manifest", required=True, help="Declarative source manifest JSON")
    args = parser.parse_args()

    try:
        manifest_integrity.verify(args.manifest)
    except (manifest_integrity.IntegrityError, OSError, ValueError) as exc:
        print(f"FAIL: cache manifest integrity: {exc}", file=sys.stderr)
        return 1

    with open(args.manifest, encoding="utf-8") as handle:
        state = json.load(handle)
    with open(args.source_manifest, encoding="utf-8") as handle:
        src = json.load(handle)

    errors = 0
    total = 0
    for key, info in state.get("artifacts", {}).items():
        total += 1
        art = src.get("artifacts", {}).get(key, {})
        dest = info.get("dest", "") or art.get("dest", "")
        full_path = resolve_artifact_path(args.ver_dir, dest)

        if info.get("status") != "ok":
            print(f"  FAIL: {key} - status={info.get('status')}")
            errors += 1
            continue
        if full_path is None:
            print(f"  FAIL: {key} - unsafe/empty dest path: {dest!r}")
            errors += 1
            continue

        full_path = artifact_path(full_path)
        if not full_path or not os.path.isfile(full_path):
            print(f"  FAIL: {key} - file missing from disk: {dest}")
            errors += 1
            continue

        recorded_sha = info.get("sha256", "")
        if not isinstance(recorded_sha, str) or not _HEX[64].match(recorded_sha):
            print(f"  FAIL: {key} - missing/invalid recorded SHA256")
            errors += 1
            continue


        try:
            actual_sha = compute_hash(full_path, "sha256")
        except OSError as exc:
            print(f"  FAIL: {key} - cannot read artifact: {exc}")
            errors += 1
            continue
        if actual_sha.lower() != recorded_sha.lower():
            print(f"  FAIL: {key} - SHA256 mismatch (artifact was modified)")
            errors += 1
            continue


        if info.get("verified"):
            if info.get("sig_verified") is not True:
                print(f"  FAIL: {key} - marked verified but PGP signature was not verified")
                errors += 1
                continue
            algo = str(info.get("hash_algo", "")).lower()
            if algo not in _STRONG_ALGOS:
                print(f"  FAIL: {key} - weak/unsupported signature hash algorithm: {algo!r}")
                errors += 1
                continue
            marker_hash = normalize_digest(info.get("hash", ""))
            expected_len = 64 if algo == "sha256" else 128
            if not _HEX[expected_len].match(marker_hash):
                print(f"  FAIL: {key} - invalid signed hash in marker")
                errors += 1
                continue
        else:

            image_digest = normalize_digest(info.get("image_digest", ""))
            pinned = normalize_digest(art.get("digest", ""))
            if not image_digest or not _HEX[64].match(image_digest):
                print(f"  FAIL: {key} - unsigned artifact has no valid image digest")
                errors += 1
                continue
            if not pinned or image_digest != pinned:
                print(f"  FAIL: {key} - image digest does not match pinned manifest digest")
                errors += 1
                continue

        detail = "PGP-verified" if info.get("verified") else "digest-pinned"
        print(f"  OK:   {key} ({info.get('size', 0)} bytes, SHA256 re-hashed, {detail})")

    print()
    print(f"Verified: {total} artifacts, {errors} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
