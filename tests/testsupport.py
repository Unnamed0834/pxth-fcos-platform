"""Shared helpers for the test suite.

Uses only the standard library so tests run with
``python3 -m pytest tests -q`` or ``python3 -m unittest discover -s tests``
without network access or external tools.
"""

import importlib.util
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "libs" / "scripts"
CI_DIR = SCRIPTS_DIR / "ci"
LIB_DIR = SCRIPTS_DIR / "lib"
HOOK = CI_DIR / "hooks" / "check-sops-encryption.sh"
PODMAN_SECRETS = LIB_DIR / "podman-secrets.sh"
VALIDATE_IMAGES = CI_DIR / "validate-images.py"


for _entry in (str(CI_DIR), str(REPO_ROOT)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)


DIGEST = "a" * 64
DOC_IP_1 = "192.0.2.10/24"
DOC_IP_2 = "198.51.100.20/24"


def shutil_which(name):
    import shutil

    result = shutil.which(name)
    if result is None:
        raise RuntimeError(f"{name} not found on PATH")
    return result


BASH = shutil_which("bash")


def load_module(name, path):
    """Import a hyphenated script file (e.g. validate-images.py) by path."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sys.modules[name] = module
    return module


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


def valid_artifact(**overrides):
    artifact = {
        "type": "url",
        "url": "https://example.com/artifacts/artifact.img",
        "dest": "images/artifact.img",
        "min_size": 1048576,
        "digest": DIGEST,
    }
    artifact.update(overrides)
    return artifact


def valid_container(name="app", image="registry.example.com/app:1.2.3", **overrides):
    artifact = {
        "type": "container",
        "image": image,
        "dest": f"containers/{name}/{name}-1.2.3.tar",
        "min_size": 1048576,
        "digest": DIGEST,
    }
    artifact.update(overrides)
    return artifact


def valid_manifest(node="node1", with_container=True):
    artifacts = {"base": valid_artifact()}
    if with_container:
        artifacts["app"] = valid_container()
    manifest = {"node": node, "artifacts": artifacts}
    if with_container:
        manifest["oem"] = {"bundle": {"containers": ["app"]}}
    return manifest


def valid_spec(node="node1", vm_id=1001, ip=DOC_IP_1, vlan=100):
    return {
        "vm_id": vm_id,
        "vm_name": node,
        "ip_address": ip,
        "vlan_id": vlan,
        "services": {},
    }


def encrypted_yaml(plaintext="token: placeholder"):
    """Return a YAML file with a realistic SOPS block and age recipient."""
    return (
        f"{plaintext}\n"
        "sops:\n"
        "  version: 3.9.0\n"
        "  age:\n"
        "    - recipient: age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq\n"
        "      enc: ENC[AES256_GCM,data:abc,iv:def,tag:ghi,type:str]\n"
        "  mac: ENC[AES256_GCM,data:xyz,iv:uvw,tag:rst,type:str]\n"
    )
