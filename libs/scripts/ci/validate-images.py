#!/usr/bin/env python3
"""Validate container image manifests, artifact pinning and cross-node wiring.

The script uses only the Python standard library and needs no network access.

Usage:
    APPS_DIR=/path/to/apps python3 validate-images.py
    python3 validate-images.py --apps-dir /path/to/apps

Manifest discovery supports both layouts:
    <apps-dir>/<node>/manifest.json             (per-app Makefiles)
    <apps-dir>/<group>/apps/<node>/manifest.json (monorepo)

For every discovered node this script checks:
  * artifact structure, destination uniqueness and container image references
  * a sane ``min_size`` and a tamper-proof pin (``digest`` or a signed
    ``digests_url`` + ``digests_asc`` pair) for every artifact
  * explicit digest pinning / destination wiring for container artifacts
  * that every container named in ``oem.bundle.containers`` is a declared
    container artifact
  * cross-node uniqueness of IP addresses, VM IDs, ports and VLAN/subnet
    assignments (read from adjacent ``node-spec.json`` files)
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


MIN_ARTIFACT_SIZE = 1024
CONTAINER_TYPES = frozenset({"container", "build"})
KNOWN_ARTIFACT_TYPES = frozenset({"url", "s3", "container", "build"})
URL_RE = re.compile(r"^https?://", re.IGNORECASE)
HEX_DIGEST_RE = re.compile(
    r"^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{40}|[0-9a-fA-F]{64}|"
    r"[0-9a-fA-F]{96}|[0-9a-fA-F]{128})$"
)
SEMVER_TAG_RE = re.compile(r"^v?\d+\.\d+")


@dataclass
class ValidationResult:
    """The outcome of one validation phase."""

    label: str = ""
    ok: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    errors: list = field(default_factory=list)

    def add_ok(self, message):
        self.ok.append(message)
        return self

    def add_warning(self, message):
        self.warnings.append(message)
        return self

    def add_error(self, message):
        self.errors.append(message)
        return self

    @property
    def is_valid(self):
        return not self.errors


def load_json(path, errors=None):
    """Load a JSON object from *path*.

    Returns the parsed dict, or ``None`` after recording a clear message in
    *errors* (when given) or on stderr.
    """
    path = Path(path)
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except FileNotFoundError:
        message = f"File not found: {path}"
    except json.JSONDecodeError as exc:
        message = f"Invalid JSON in {path}: {exc}"
    except OSError as exc:
        message = f"Cannot read {path}: {exc}"
    else:
        if not isinstance(data, dict):
            message = f"Manifest root must be a JSON object: {path}"
        else:
            return data

    if errors is not None:
        errors.append(message)
    else:
        print(f"ERROR: {message}", file=sys.stderr)
    return None


def is_valid_digest(value):
    """True when *value* looks like a real hex digest (MD5..SHA512)."""
    return isinstance(value, str) and bool(HEX_DIGEST_RE.match(value.strip()))


def is_signed_digest_source(artifact):
    """True when both a digest file and its detached signature are declared."""
    urls = (artifact.get("digests_url"), artifact.get("digests_asc"))
    return all(
        isinstance(url, str) and bool(URL_RE.match(url.strip())) for url in urls
    )


def _artifacts_of(manifest):
    artifacts = manifest.get("artifacts")
    return artifacts if isinstance(artifacts, dict) else {}


def _image_tag(image):
    last = image.rsplit("/", 1)[-1]
    if "@sha256:" in last:
        return None
    if ":" in last:
        return last.rsplit(":", 1)[1]
    return ""


def validate_node(node, manifest_path):
    """Phase 1: structure, destinations and container image references."""
    result = ValidationResult(label=node)
    manifest = load_json(manifest_path, result.errors)
    if manifest is None:
        return result

    name = manifest.get("node")
    if not isinstance(name, str) or not name.strip():
        result.add_error("Missing or empty 'node' field")
    elif name != node:
        result.add_warning(
            f"'node' field ({name!r}) does not match directory name ({node!r})"
        )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        result.add_error("Missing or empty 'artifacts' object")
        return result
    if "oem" not in manifest:
        result.add_warning("No 'oem' section: node will not produce an OEM bundle")

    destinations = {}
    for key, artifact in artifacts.items():
        if not isinstance(artifact, dict):
            result.add_error(f"artifact {key!r} must be a JSON object")
            continue

        atype = artifact.get("type")
        if atype not in KNOWN_ARTIFACT_TYPES:
            result.add_error(f"artifact {key!r} has unsupported type {atype!r}")

        dest = artifact.get("dest")
        if not isinstance(dest, str) or not dest.strip():
            result.add_error(f"artifact {key!r} has no 'dest' path")
        else:
            if dest in destinations:
                result.add_error(
                    f"duplicate destination {dest!r} used by artifacts "
                    f"{destinations[dest]!r} and {key!r}"
                )
            else:
                destinations[dest] = key
            if atype in CONTAINER_TYPES and not (
                dest.startswith("containers/") and dest.endswith(".tar")
            ):
                result.add_error(
                    f"container artifact {key!r} dest must be 'containers/...tar': {dest!r}"
                )

        if atype in CONTAINER_TYPES:
            image = artifact.get("image")
            if not isinstance(image, str) or not image.strip():
                result.add_error(f"container artifact {key!r} has no 'image' reference")
            else:
                tag = _image_tag(image)
                if tag == "":
                    result.add_warning(
                        f"container artifact {key!r} image {image!r} has no tag or digest"
                    )
                elif tag is not None and not SEMVER_TAG_RE.match(tag):
                    result.add_warning(
                        f"container artifact {key!r} image tag {tag!r} is not semver-like"
                    )

    if not result.errors:
        result.add_ok(f"{len(artifacts)} artifact(s) structurally valid")
    return result


def validate_manifest_digests(node, manifest_path):
    """Phase 2: min_size and a tamper-proof pin for every artifact."""
    result = ValidationResult(label=node)
    manifest = load_json(manifest_path, result.errors)
    if manifest is None:
        return result

    artifacts = _artifacts_of(manifest)
    if not artifacts:
        result.add_error("No artifacts to validate")
        return result

    for key, artifact in artifacts.items():
        if not isinstance(artifact, dict):
            continue

        min_size = artifact.get("min_size")
        if (
            not isinstance(min_size, int)
            or isinstance(min_size, bool)
            or min_size < MIN_ARTIFACT_SIZE
        ):
            result.add_error(
                f"artifact {key!r} has invalid min_size {min_size!r} "
                f"(expected integer >= {MIN_ARTIFACT_SIZE})"
            )

        digest = artifact.get("digest")
        digests_url = artifact.get("digests_url")
        digests_asc = artifact.get("digests_asc")
        has_digest = is_valid_digest(digest)
        has_signed = is_signed_digest_source(artifact)

        if digest is not None and not has_digest:
            result.add_error(f"artifact {key!r} has malformed 'digest': {digest!r}")
        if bool(digests_url) != bool(digests_asc):
            result.add_error(
                f"artifact {key!r} has an incomplete signed digest pair: "
                "'digests_url' and 'digests_asc' must both be set"
            )
        if not has_digest and not has_signed:
            result.add_error(
                f"artifact {key!r} has neither a valid 'digest' nor signed "
                "'digests_url' + 'digests_asc'"
            )

        if has_digest:
            result.add_ok(f"artifact {key!r} pinned by digest")
        elif has_signed:
            result.add_ok(f"artifact {key!r} pinned by signed digest files")
    return result


def validate_digest_wiring(node, manifest_path):
    """Phase 3: container artifacts pin an image digest and wire it to a dest."""
    result = ValidationResult(label=node)
    manifest = load_json(manifest_path, result.errors)
    if manifest is None:
        return result

    containers = 0
    for key, artifact in _artifacts_of(manifest).items():
        if not isinstance(artifact, dict) or artifact.get("type") not in CONTAINER_TYPES:
            continue
        containers += 1
        if not is_valid_digest(artifact.get("digest")):
            result.add_error(
                f"container artifact {key!r} must pin an explicit image 'digest'; "
                "signed digests_url/digests_asc are not sufficient for runtime pulls"
            )
        if not isinstance(artifact.get("image"), str) or not artifact["image"].strip():
            result.add_error(
                f"container artifact {key!r} has no image reference to wire the digest to"
            )
        dest = artifact.get("dest")
        if not isinstance(dest, str) or not (
            dest.startswith("containers/") and dest.endswith(".tar")
        ):
            result.add_error(
                f"container artifact {key!r} must wire its image to 'containers/...tar': {dest!r}"
            )

    if not result.errors:
        result.add_ok(f"{containers} container artifact(s) pinned and wired by digest")
    return result


def validate_bundle_containers(node, manifest_path):
    """Phase 4: OEM bundle containers must be declared container artifacts."""
    result = ValidationResult(label=node)
    manifest = load_json(manifest_path, result.errors)
    if manifest is None:
        return result

    oem = manifest.get("oem")
    if not isinstance(oem, dict):
        return result
    bundle = oem.get("bundle", {})
    if not isinstance(bundle, dict):
        result.add_error("'oem.bundle' must be a JSON object")
        return result

    names = bundle.get("containers", [])
    if not isinstance(names, list):
        result.add_error("'oem.bundle.containers' must be a list")
        return result

    artifacts = _artifacts_of(manifest)
    for name in names:
        if not isinstance(name, str) or name not in artifacts:
            result.add_error(
                f"OEM bundle container {name!r} is not declared in 'artifacts'"
            )
            continue
        artifact = artifacts[name]
        if not isinstance(artifact, dict) or artifact.get("type") not in CONTAINER_TYPES:
            result.add_error(
                f"OEM bundle container {name!r} is not a container/build artifact"
            )
        else:
            result.add_ok(f"bundle container {name!r} is declared and pinned")

    return result


def _subnet_of(ip):
    """Return the /24 subnet key of an IP (with or without a prefix)."""
    address = ip.split("/", 1)[0]
    octets = address.split(".")
    if len(octets) != 4:
        return None
    return ".".join(octets[:3]) + ".0/24"


def validate_cross_node(specs):
    """Check IP / VMID / port / VLAN uniqueness across node-spec dictionaries."""
    result = ValidationResult(label="cross-node")
    ip_owners = {}
    vmid_owners = {}
    port_owners = {}
    subnet_vlans = {}
    vlan_subnets = {}

    for node, spec in sorted(specs.items()):
        if not isinstance(spec, dict):
            result.add_error(f"node-spec for {node!r} must be a JSON object")
            continue

        instances = []
        if "vm_id" in spec or "ip_address" in spec:
            instances.append(spec)
        for entry in spec.get("nodes", []) if isinstance(spec.get("nodes", []), list) else []:
            if isinstance(entry, dict):
                instances.append(entry)

        instance_ips = []
        for entry in instances:
            label = (
                entry.get("name")
                or entry.get("hostname")
                or entry.get("vm_name")
                or node
            )
            ip = entry.get("ip_address")
            if isinstance(ip, str) and ip.strip():
                instance_ips.append(ip)
                if ip in ip_owners and ip_owners[ip] != label:
                    result.add_error(
                        f"IP conflict: {ip} used by both {ip_owners[ip]!r} and {label!r}"
                    )
                else:
                    ip_owners[ip] = label

                subnet = _subnet_of(ip)
                vlan = entry.get("vlan_id", spec.get("vlan_id"))
                if subnet is not None and isinstance(vlan, int) and not isinstance(vlan, bool):
                    subnet_vlans.setdefault(subnet, set()).add(vlan)
                    vlan_subnets.setdefault(vlan, set()).add(subnet)

            vmid = entry.get("vm_id")
            if isinstance(vmid, int) and not isinstance(vmid, bool):
                if vmid in vmid_owners and vmid_owners[vmid] != label:
                    result.add_error(
                        f"VM ID conflict: vm_id={vmid} used by both "
                        f"{vmid_owners[vmid]!r} and {label!r}"
                    )
                else:
                    vmid_owners[vmid] = label

        services = spec.get("services", {})
        if isinstance(services, dict):
            for svc_name, svc in services.items():
                ports = svc.get("ports", []) if isinstance(svc, dict) else []
                for port_info in ports if isinstance(ports, list) else []:
                    host_port = (
                        port_info.get("host_port") or port_info.get("hostPort")
                        if isinstance(port_info, dict)
                        else None
                    )
                    if host_port is None:
                        continue
                    for ip in instance_ips:
                        key = (ip, host_port)
                        if key in port_owners and port_owners[key] != node:
                            result.add_error(
                                f"port conflict: {host_port} bound on {ip} by both "
                                f"{port_owners[key]!r} and {node!r} (service {svc_name!r})"
                            )
                        else:
                            port_owners[key] = node

    for subnet, vlans in sorted(subnet_vlans.items()):
        if len(vlans) > 1:
            result.add_error(
                f"VLAN conflict: subnet {subnet} is assigned to multiple VLANs "
                f"({', '.join(str(v) for v in sorted(vlans))})"
            )
    for vlan, subnets in sorted(vlan_subnets.items()):
        if len(subnets) > 1:
            result.add_warning(
                f"VLAN {vlan} spans multiple subnets: {', '.join(sorted(subnets))}"
            )

    if not result.errors and specs:
        result.add_ok(
            f"{len(specs)} node-spec(s): IPs, VM IDs, ports and VLANs are unique"
        )
    return result


def discover_manifests(apps_dir):
    """Return ``(node, manifest_path, spec_path)`` tuples for all manifests."""
    base = Path(apps_dir)
    found = []
    seen = set()
    if not base.is_dir():
        return found
    for pattern in ("*/manifest.json", "*/apps/*/manifest.json"):
        for manifest_path in sorted(base.glob(pattern)):
            resolved = manifest_path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            found.append(
                (
                    manifest_path.parent.name,
                    resolved,
                    resolved.parent / "node-spec.json",
                )
            )
    return found


def collect_results(apps_dir):
    """Run every validation phase and return the list of results."""
    results = []
    nodes = discover_manifests(apps_dir)
    if not nodes:
        empty = ValidationResult(label="discovery")
        empty.add_error(
            f"No manifests found under {apps_dir}; expected '*/manifest.json' "
            "or '*/apps/*/manifest.json'"
        )
        results.append(empty)
        return results

    specs = {}
    for node, manifest_path, spec_path in nodes:
        phases = (
            validate_node,
            validate_manifest_digests,
            validate_digest_wiring,
            validate_bundle_containers,
        )
        for phase in phases:
            phase_result = phase(node, manifest_path)

            if phase_result.ok or phase_result.warnings or phase_result.errors:
                results.append(phase_result)
        if spec_path.is_file():
            spec = load_json(spec_path)
            if spec is not None:
                specs[node] = spec

    results.append(validate_cross_node(specs))
    return results


def run_validation(apps_dir, stream=None):
    """Print the report and return a process exit code (0 = all checks passed)."""
    stream = stream if stream is not None else sys.stdout
    results = collect_results(apps_dir)
    total_errors = 0

    print("========================================", file=stream)
    print("Container Image Validation", file=stream)
    print("========================================", file=stream)
    print(file=stream)

    for result in results:
        if not (result.ok or result.warnings or result.errors):
            continue
        print(f"Node: {result.label}", file=stream)
        for message in result.ok:
            print(f"  OK: {message}", file=stream)
        for message in result.warnings:
            print(f"  WARN: {message}", file=stream)
        for message in result.errors:
            print(f"  FAIL: {message}", file=stream)
        print(file=stream)
        total_errors += len(result.errors)

    print("========================================", file=stream)
    if total_errors == 0:
        print("PASS: All container images and wiring validated", file=stream)
        return 0

    print(f"FAIL: {total_errors} issue(s) found", file=stream)
    print(file=stream)
    print("Fix options:", file=stream)
    print("  1. Run: pcache sync <node> to populate digests in manifest.json", file=stream)
    print("  2. Add digest + digests_url/digests_asc to every artifact", file=stream)
    print("  3. Ensure OEM bundle containers are declared artifacts", file=stream)
    print("  4. Resolve cross-node IP/VMID/VLAN/port conflicts", file=stream)
    return 1


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate container image manifests and cross-node wiring"
    )
    parser.add_argument(
        "--apps-dir",
        default=os.environ.get("APPS_DIR"),
        help="apps directory (defaults to $APPS_DIR or the repository apps/ dir)",
    )
    args = parser.parse_args(argv)
    apps_dir = args.apps_dir or str(Path(__file__).resolve().parents[3] / "apps")
    return run_validation(apps_dir)


if __name__ == "__main__":
    sys.exit(main())
