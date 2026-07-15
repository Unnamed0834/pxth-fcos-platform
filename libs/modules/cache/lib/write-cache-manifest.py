#!/usr/bin/env python3
"""Write .cache-manifest.json state record for a version directory.

The declarative node manifest is READ-ONLY. Runtime observations (hashes,
sizes, image digests, signature state) are recorded only in the cache state
record and its HMAC sidecar. Nothing is ever written back to manifest.json.

Usage:
  python3 write-cache-manifest.py --manifest <output> --ver-dir <path>
      --node <name> --source-manifest <declarative-manifest.json>
"""

import argparse
import datetime
import hashlib
import json
import os
import sys

import manifest_integrity


def compute_hash(filepath, algo="sha512"):
    """Compute a hash of a file (streaming)."""
    digest = hashlib.new(algo)
    with open(filepath, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_info(art_path):
    """Compute size and SHA256 for an artifact file (or first .tar in a dir)."""
    result = {"status": "missing", "size": 0, "sha256": ""}
    if not art_path or not os.path.exists(art_path):
        return result
    if os.path.isdir(art_path):
        for fname in sorted(os.listdir(art_path)):
            if fname.endswith(".tar"):
                art_path = os.path.join(art_path, fname)
                break
        else:
            return result
    if not os.path.isfile(art_path):
        return result
    result["status"] = "ok"
    result["size"] = os.path.getsize(art_path)
    result["sha256"] = compute_hash(art_path, "sha256")
    return result


def read_verified_marker(filepath):
    """Read a .verified marker file into a dict (no shell, no eval)."""
    marker_path = filepath + ".verified"
    if not os.path.isfile(marker_path):
        return None
    result = {}
    with open(marker_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if "=" in line:
                key, _, value = line.partition("=")
                result[key.strip()] = value.strip()
    return result


def main():
    parser = argparse.ArgumentParser(description="Write cache manifest state record")
    parser.add_argument("--manifest", required=True, help="Output cache manifest path")
    parser.add_argument("--ver-dir", required=True, help="Version directory")
    parser.add_argument("--node", required=True, help="Node name")
    parser.add_argument("--source-manifest", required=True, help="Source manifest JSON (read-only)")
    args = parser.parse_args()

    try:
        with open(args.source_manifest, encoding="utf-8") as handle:
            source = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"write-cache-manifest: cannot read source manifest: {exc}", file=sys.stderr)
        return 1

    artifacts_info = {}
    for key, definition in source.get("artifacts", {}).items():
        dest = definition.get("dest", "")
        full_path = os.path.join(args.ver_dir, dest) if dest else ""
        info = artifact_info(full_path)
        info["dest"] = dest

        digest_file = full_path + ".digest" if full_path else ""
        if digest_file and os.path.isfile(digest_file):
            with open(digest_file, encoding="utf-8") as handle:
                digest = handle.read().strip()
            if digest:
                info["image_digest"] = digest

        marker = read_verified_marker(full_path)
        if marker:
            info["verified"] = True
            info["verified_at"] = marker.get("verified_at", "")
            info["hash_algo"] = marker.get("hash_algo", "")
            info["hash"] = marker.get("hash", "")
            info["sig_verified"] = marker.get("sig_verified", "false") == "true"
            info["signer_fingerprint"] = marker.get("signer_fingerprint", "")
            if os.path.isfile(full_path):
                info["sha512"] = compute_hash(full_path, "sha512")
        else:
            info["verified"] = False

        artifacts_info[key] = info

    result = {
        "node": args.node,
        "version": "v1",
        "synced_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "artifacts": artifacts_info,
    }

    out_dir = os.path.dirname(args.manifest) or "."
    os.makedirs(out_dir, exist_ok=True)
    with open(args.manifest, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")


    try:
        manifest_integrity.sign(args.manifest)
    except (manifest_integrity.IntegrityError, OSError, ValueError) as exc:
        print(f"write-cache-manifest: {exc}", file=sys.stderr)
        return 1

    print(f"Cache manifest written and HMAC-signed: {args.manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
