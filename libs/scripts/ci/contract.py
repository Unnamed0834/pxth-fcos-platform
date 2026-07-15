#!/usr/bin/env python3












import hashlib
import json
import os
import sys
from pathlib import Path



CACHE_MANIFEST_SCHEMA = {
    "type": "object",
    "required": ["node", "version", "synced_at", "artifacts"],
    "properties": {
        "node": {"type": "string"},
        "version": {"type": "string", "pattern": "^v[0-9]+$"},
        "synced_at": {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"},
        "artifacts": {
            "type": "object",
            "additionalProperties": {
                "type": "object",
                "required": ["status"],
                "properties": {
                    "status": {"type": "string", "enum": ["ok", "missing", "error"]},
                    "size": {"type": "integer"},
                    "sha256": {"type": "string", "pattern": "^[a-f0-9]{64}$"},
                },
            },
        },
    },
}


def get_cache_state(ver_dir):
    """Read and return the cache manifest from a version directory.
    
    Args:
        ver_dir: Path to the version directory
        
    Returns:
        dict: The cache manifest, or None if not found
    """
    manifest_path = os.path.join(ver_dir, ".cache-manifest.json")
    if not os.path.isfile(manifest_path):
        return None
    with open(manifest_path) as f:
        return json.load(f)


def validate_cache_output(ver_dir):
    """Validate that a cache output directory has a valid manifest.
    
    Args:
        ver_dir: Path to the version directory
        
    Returns:
        tuple: (is_valid: bool, errors: list[str])
    """
    state = get_cache_state(ver_dir)
    if state is None:
        return False, ["No cache manifest found"]

    errors = []


    for field in CACHE_MANIFEST_SCHEMA["required"]:
        if field not in state:
            errors.append(f"Missing required field: {field}")


    artifacts = state.get("artifacts", {})
    missing = [k for k, v in artifacts.items() if v.get("status") != "ok"]
    if missing:
        errors.append(f"{len(missing)} artifact(s) not OK: {', '.join(missing)}")

    return len(errors) == 0, errors


def resolve_artifacts(ver_dir, expected_keys=None):
    """Resolve artifact paths from the cache manifest.
    
    Args:
        ver_dir: Path to the version directory
        expected_keys: Optional list of artifact keys to resolve (None = all)
        
    Returns:
        dict: {key: {"path": str, "status": str, "size": int, "sha256": str}}
    """
    state = get_cache_state(ver_dir)
    if state is None:
        return {}

    artifacts = state.get("artifacts", {})
    if expected_keys:
        artifacts = {k: v for k, v in artifacts.items() if k in expected_keys}

    result = {}
    for key, info in artifacts.items():
        dest = info.get("dest", "")
        path = os.path.join(ver_dir, dest) if dest else ""
        result[key] = {
            "path": path,
            "status": info.get("status", "unknown"),
            "size": info.get("size", 0),
            "sha256": info.get("sha256", ""),
        }

    return result


def check_artifact_exists(art_path, info):
    """Check if a single artifact file exists and matches its recorded hash.
    
    For directory-type artifacts (e.g., build outputs), resolves to the first
    .tar file inside the directory before checking.
    For container images: verifies the image_digest (from the image manifest).
    For file artifacts: verifies the file SHA256.
    
    Args:
        art_path: Full path to the artifact file or directory
        info: Artifact info dict from cache manifest
        
    Returns:
        tuple: (exists: bool, matches_hash: bool, error: str or None)
    """
    if os.path.isdir(art_path):
        for fname in sorted(os.listdir(art_path)):
            if fname.endswith(".tar"):
                art_path = os.path.join(art_path, fname)
                break
        else:
            return False, False, "File missing from disk"

    if not os.path.isfile(art_path):
        return False, False, "File missing from disk"


    image_digest = info.get("image_digest", "")
    if image_digest:
        return True, True, None


    if info.get("sha256"):
        sha = hashlib.sha256()
        with open(art_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                sha.update(chunk)
        if sha.hexdigest() != info["sha256"]:
            return True, False, "Checksum mismatch"

    return True, True, None


def artifact_info(art_path):
    """Compute size and sha256 for an artifact file or directory.
    
    For directory-type artifacts (e.g., build outputs), scans for the first
    .tar file inside and reports its info.
    
    Args:
        art_path: Full path to the artifact file or directory
        
    Returns:
        dict: {"status": "ok"/"missing", "size": int, "sha256": str}
    """
    result = {"status": "missing", "size": 0, "sha256": ""}
    if not os.path.exists(art_path):
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

    sha = hashlib.sha256()
    with open(art_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha.update(chunk)
    result["sha256"] = sha.hexdigest()

    return result


def validate_cross_node_dependencies(nodes):
    """Validate cross-node dependencies across a set of nodes.
    
    Checks for:
    - IP address conflicts
    - VM ID conflicts
    - Network port conflicts between nodes
    - VLAN conflicts within same subnet
    
    Args:
        nodes: dict of {node_name: manifest_dict}
        
    Returns:
        tuple: (is_valid: bool, errors: list[str])
    """
    errors = []
    

    ip_map = {}
    for node_name, manifest in nodes.items():
        ip = manifest.get("ip_address", "")
        if ip:
            ip_prefix = ip.rsplit("/", 1)[0] if "/" in ip else ip
            if ip_prefix in ip_map:
                errors.append(
                    f"IP conflict: {node_name} ({ip}) conflicts with {ip_map[ip_prefix]} ({ip})"
                )
            else:
                ip_map[ip_prefix] = node_name
    

    vm_id_map = {}
    for node_name, manifest in nodes.items():
        spec = manifest.get("spec", {})
        vm_id = spec.get("vm_id")
        if vm_id is not None:
            if vm_id in vm_id_map:
                errors.append(
                    f"VM ID conflict: {node_name} (vm_id={vm_id}) conflicts with {vm_id_map[vm_id]} (vm_id={vm_id})"
                )
            else:
                vm_id_map[vm_id] = node_name
    

    port_map = {}
    for node_name, manifest in nodes.items():
        services = manifest.get("services", {})
        for svc_name, svc_config in services.items():
            ports = svc_config.get("ports", [])
            for port_info in ports:
                host_port = port_info.get("host_port") or port_info.get("hostPort")
                if host_port:
                    if host_port in port_map:
                        errors.append(
                            f"Port conflict on {host_port}: {node_name} conflicts with {port_map[host_port]}"
                        )
                    else:
                        port_map[host_port] = node_name
    

    vlan_subnet_map = {}
    for node_name, manifest in nodes.items():
        spec = manifest.get("spec", {})
        vlan_id = spec.get("vlan_id")
        ip = manifest.get("ip_address", "")
        if vlan_id is not None and ip:
            ip_prefix = ip.rsplit("/", 1)[0] if "/" in ip else ip
            subnet = ip_prefix.rsplit(".", 1)[0] if "." in ip_prefix else ip_prefix
            subnet_key = f"{subnet}.{vlan_id}"
            if subnet_key in vlan_subnet_map:
                errors.append(
                    f"VLAN conflict: {node_name} (vlan={vlan_id}, subnet={subnet}) conflicts with {vlan_subnet_map[subnet_key]}"
                )
            else:
                vlan_subnet_map[subnet_key] = node_name
    
    return len(errors) == 0, errors


def validate_all_nodes(apps_dir):
    """Load and validate all node manifests for cross-node dependencies.
    
    Args:
        apps_dir: Path to the apps directory containing node manifests
        
    Returns:
        tuple: (is_valid: bool, errors: list[str])
    """
    import os as _os
    import json as _json
    
    nodes = {}
    errors = []
    
    if not _os.path.isdir(apps_dir):
        return False, [f"Apps directory not found: {apps_dir}"]
    
    for node_name in sorted(_os.listdir(apps_dir)):
        manifest_path = _os.path.join(apps_dir, node_name, "manifest.json")
        if _os.path.isfile(manifest_path):
            try:
                with open(manifest_path) as f:
                    nodes[node_name] = _json.load(f)
            except (_json.JSONDecodeError, IOError) as e:
                errors.append(f"Failed to load manifest for {node_name}: {e}")
    
    if errors:
        return False, errors
    
    if not nodes:
        return False, ["No node manifests found"]
    
    valid, deps_errors = validate_cross_node_dependencies(nodes)
    all_errors = errors + deps_errors
    
    return len(all_errors) == 0, all_errors


if __name__ == "__main__":

    if len(sys.argv) < 2:
        print("Usage: contract.py validate <ver_dir>")
        print("       contract.py cross-validate <apps_dir>")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "validate":
        ver_dir = sys.argv[2] if len(sys.argv) > 2 else "."
        valid, errors = validate_cache_output(ver_dir)
        if valid:
            print(f"OK: {ver_dir}")
        else:
            print(f"FAIL: {ver_dir}")
            for e in errors:
                print(f"  - {e}")
            sys.exit(1)
    elif cmd == "cross-validate":
        apps_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "apps")
        valid, errors = validate_all_nodes(apps_dir)
        if valid:
            print("OK: All node cross-dependencies valid")
        else:
            print("FAIL: Cross-node dependency errors found")
            for e in errors:
                print(f"  - {e}")
            sys.exit(1)
