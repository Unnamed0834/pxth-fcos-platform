# Shared scripts

Standard-library Python and POSIX shell. Self-tests need no network access or credentials.

All shell entrypoints use `set -euo pipefail`, quoted variables, and `mktemp` with an `EXIT` trap.
Python entrypoints use argument lists for subprocesses and an `__main__` guard.

## `ci/`

| Path | Purpose |
| --- | --- |
| `validate-images.py` | validates manifests, digest pins, bundle wiring, and cross-node IP/VMID/port/VLAN uniqueness |
| `contract.py` | cache manifest schema and artifact-path rules |
| `libpath.py` | imports hyphenated sibling modules |
| `lib/` | shared artifact and logging helpers |

## `ci/hooks/`

| Path | Purpose |
| --- | --- |
| `check-sops-encryption.sh` | requires real SOPS metadata, successful decryption, and no residual ciphertext for every non-Markdown file under `secrets/` |
| `lib/hook-common.sh` | shared hook helpers |

## `lib/`

| Path | Purpose |
| --- | --- |
| `podman-secrets.sh` | private `mktemp` staging, 0600, `EXIT` trap, argv-array `podman secret create` |
| `list-nodes.py` | lists nodes from manifests |
| `resolve-secrets.py`, `resolve-variables.py` | resolve encrypted secrets and variables |
| `tf-config.sh` | generates root Terraform configuration |
