#!/usr/bin/env python3







import argparse
import hashlib
import os


def main():
    parser = argparse.ArgumentParser(description="Create OEM disk image")
    parser.add_argument("--tarball", required=True, help="Input tarball path")
    parser.add_argument("--output", required=True, help="Output raw disk path")
    parser.add_argument("--headroom", type=int, default=64, help="Headroom in MB")
    parser.add_argument("--hash-file", default="", help="Optional file to write disk SHA256")
    args = parser.parse_args()

    tar_size = os.path.getsize(args.tarball)
    disk_size_mb = (tar_size + 1048575) // 1048576 + args.headroom

    print(f"  Tarball: {tar_size // (1024*1024)} MB  ->  Disk: {disk_size_mb} MB")


    os.makedirs(os.path.dirname(args.output) if os.path.dirname(args.output) else ".", exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(b"\0" * (disk_size_mb * 1024 * 1024))


    with open(args.tarball, "rb") as f:
        tarball_data = f.read()

    with open(args.output, "r+b") as f:
        f.write(tarball_data)

    print(f"  Embedded {len(tarball_data)} bytes into {disk_size_mb} MB disk")


    disk_sha256 = hashlib.sha256()
    with open(args.output, "rb") as f:
        while True:
            chunk = f.read(1048576)
            if not chunk:
                break
            disk_sha256.update(chunk)
    disk_sha256_hex = disk_sha256.hexdigest()
    disk_size_bytes = disk_size_mb * 1024 * 1024

    print(f"  Disk SHA256: {disk_sha256_hex}")
    print(f"  Disk Bytes:  {disk_size_bytes}")

    if args.hash_file:
        os.makedirs(os.path.dirname(args.hash_file) if os.path.dirname(args.hash_file) else ".", exist_ok=True)
        with open(args.hash_file, "w") as f:
            f.write(disk_sha256_hex)
        print(f"  Hash:  {args.hash_file}")


if __name__ == "__main__":
    main()
