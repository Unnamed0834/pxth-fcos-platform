#!/usr/bin/env python3
"""Pack an OEM bundle by copying artifacts into a directory structure.

Runtime secrets are NOT part of the bundle. They are delivered out-of-band to
/run/secrets/<name>.env by the operator/systemd credentials and are read at
runtime by the node. This script never reads a repository `secrets/` tree and
never writes decrypted `.env` files into the bundle or onto disk.

Usage: python3 pack-bundle.py --bundle-dir <path> --manifest <manifest.json>
                              --ver-dir <path> [--inference-engine <name>]
                              [--node-name <name>]
"""

import argparse
import glob
import json
import os
import shutil
import sys


def _within(base, target):
    """True when target resolves inside base (path-traversal guard)."""
    base_real = os.path.realpath(base)
    target_real = os.path.realpath(target)
    try:
        return os.path.commonpath([base_real, target_real]) == base_real
    except ValueError:
        return False


def main():
    parser = argparse.ArgumentParser(description="Pack OEM bundle (no secrets)")
    parser.add_argument("--bundle-dir", required=True, help="Destination bundle directory")
    parser.add_argument("--manifest", required=True, help="Node manifest JSON")
    parser.add_argument("--ver-dir", required=True, help="Source version directory")
    parser.add_argument("--inference-engine", default="", help="Override active container")
    parser.add_argument("--node-name", default="", help="Subnode name (artifact scoping only)")
    args = parser.parse_args()

    if os.path.exists(args.bundle_dir):
        shutil.rmtree(args.bundle_dir)
    os.makedirs(args.bundle_dir)

    manifest_dir = os.path.dirname(os.path.abspath(args.manifest))
    repo_root = os.environ.get("REPO_ROOT", os.path.dirname(os.path.dirname(manifest_dir)))

    with open(args.manifest, encoding="utf-8") as handle:
        node_def = json.load(handle)

    oem = node_def.get("oem", {})
    bundle_conf = oem.get("bundle", {})


    oem_active = oem.get("active", "")
    selected = args.inference_engine if args.inference_engine and oem_active else oem_active
    if selected:
        artifact_keys = set(node_def.get("artifacts", {}).keys())
        if selected not in artifact_keys:
            print(f"  ERROR: Active container '{selected}' not found in artifacts. "
                  f"Available: {', '.join(sorted(artifact_keys))}")
            return 1
    print(f"  Active container: {selected}")

    def copy_artifact(pattern, subdirectory):
        dest_dir = os.path.join(args.bundle_dir, subdirectory)
        for src in glob.glob(os.path.join(args.ver_dir, pattern)):
            if not _within(args.ver_dir, src):
                print(f"  WARN: Refusing out-of-tree artifact: {src}")
                continue
            os.makedirs(dest_dir, exist_ok=True)
            shutil.copy2(src, dest_dir)
            print(f"  Copied {subdirectory}: {os.path.basename(src)}")


    for pattern in bundle_conf.get("sysext", []):
        copy_artifact(pattern, "sysext")
    for pattern in bundle_conf.get("bin", []):
        copy_artifact(pattern, "bin")

    def copy_container(key):
        con_src = os.path.join(args.ver_dir, "containers", key)
        if os.path.isdir(con_src) and _within(args.ver_dir, con_src):
            con_dest = os.path.join(args.bundle_dir, "containers", key)
            os.makedirs(con_dest, exist_ok=True)
            for fname in sorted(os.listdir(con_src)):
                if fname.endswith(".tar"):
                    shutil.copy2(os.path.join(con_src, fname), con_dest)
                    print(f"  Copied container: {key}/{fname}")
        else:
            print(f"  WARN: Container not found: {key}")

    if selected:
        copy_container(selected)
    for key in bundle_conf.get("containers", []):
        copy_container(key)

    def copy_source(entry):
        if isinstance(entry, str):
            src_path = os.path.join(repo_root, entry)
            dest_rel = os.path.basename(entry)
        elif isinstance(entry, dict):
            src_path = os.path.join(repo_root, entry.get("path", ""))
            dest_rel = entry.get("dest", os.path.basename(entry.get("path", "")))
        else:
            return
        if os.path.isabs(dest_rel) or ".." in dest_rel.replace("\\", "/").split("/"):
            print(f"  WARN: Refusing unsafe bundle destination: {dest_rel!r}")
            return
        dest_path = os.path.join(args.bundle_dir, dest_rel)
        if not _within(args.bundle_dir, dest_path):
            print(f"  WARN: Refusing out-of-bundle destination: {dest_rel!r}")
            return
        real_src = os.path.realpath(src_path)

        if os.path.sep + "secrets" + os.path.sep in real_src + os.path.sep:
            print(f"  WARN: Refusing to bundle a secrets path: {src_path}")
            return
        if os.path.isfile(src_path):
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            shutil.copy2(src_path, dest_path)
            print(f"  Copied source: {src_path} -> {dest_rel}")
        else:
            print(f"  WARN: Source not found: {src_path}")

    sources = bundle_conf.get("sources", [])
    if sources:
        for entry in sources:
            copy_source(entry)
    else:

        for script_path in bundle_conf.get("scripts", []):
            src_path = os.path.join(repo_root, script_path)
            real_src = os.path.realpath(src_path)
            if os.path.sep + "secrets" + os.path.sep in real_src + os.path.sep:
                print(f"  WARN: Refusing to bundle a secrets path: {src_path}")
                continue
            dest_dir = os.path.join(args.bundle_dir, "scripts")
            if os.path.isfile(src_path):
                os.makedirs(dest_dir, exist_ok=True)
                shutil.copy2(src_path, dest_dir)
                print(f"  Copied script: {os.path.basename(script_path)}")
        for lib_path in bundle_conf.get("shared_libs", []):
            src_path = os.path.join(repo_root, lib_path)
            real_src = os.path.realpath(src_path)
            if os.path.sep + "secrets" + os.path.sep in real_src + os.path.sep:
                print(f"  WARN: Refusing to bundle a secrets path: {src_path}")
                continue
            dest_dir = os.path.join(args.bundle_dir, "scripts", "lib")
            if os.path.isfile(src_path):
                os.makedirs(dest_dir, exist_ok=True)
                shutil.copy2(src_path, dest_dir)
                print(f"  Copied shared lib: {os.path.basename(lib_path)}")

    print("  Bundle contains artifacts only (no secrets).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
