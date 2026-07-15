#!/usr/bin/env python3








import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Resolve artifact definitions")
    parser.add_argument("--manifest", required=True, help="Node manifest JSON")
    parser.add_argument("--key", default="", help="Specific artifact key to resolve")
    args = parser.parse_args()

    with open(args.manifest) as f:
        m = json.load(f)

    artifacts = m.get("artifacts", {})

    if not args.key:

        for key in artifacts:
            print(key)
    else:

        if args.key not in artifacts:
            print("|||0", file=sys.stderr)
            sys.exit(1)
        a = artifacts[args.key]
        algo = str(a.get("hash_algo", "sha512")).lower()
        if algo not in ("sha256", "sha512"):


            print(f"weak/unsupported hash_algo rejected: {algo!r}", file=sys.stderr)
            sys.exit(1)
        a["hash_algo"] = algo
        print("|".join([
            a.get("type", ""),
            a.get("url", ""),
            a.get("dest", ""),
            a.get("image", ""),
            str(a.get("min_size", 1024)),
            a.get("digests_url", ""),
            a.get("digests_asc", ""),
            a.get("hash_algo", "sha512"),
            a.get("gpg_key", ""),
            a.get("digest", ""),
            a.get("bucket", ""),
            a.get("key", ""),
            a.get("endpoint", ""),
        ]))


if __name__ == "__main__":
    main()
