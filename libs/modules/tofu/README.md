# pxth-tofu

Shared OpenTofu module tree. The deploy orchestrator copies this directory into a `mktemp` workspace,
generates a root config, and runs `tofu init / plan / apply`.

## Deploy contract

- Secrets arrive via `TF_VAR_*` and a `0600` sensitive variable file. No module builds a shell command
  from a secret, writes secrets into state through a validation resource, or reads a token with
  `curl`. All secret variables and outputs use `sensitive = true`.
- Firewall rules are declarative. There is no cluster-wide SDN deletion and no `curl`-based rule
  deletion. DNS is configurable; there is no default public resolver.
- Butane rendering uses `strict = true`. VM initialization diffs are applied rather than ignored, and
  missing OEM metadata fails at plan time. Preflight checks paths only, under an explicit `bash` with
  `set -euo pipefail`.
- Artifact paths are absolute values passed by the orchestrator; nothing is derived from
  `path.module`, which is a temporary copy during deploy.

## Module tree

| Module | Responsibility |
| --- | --- |
| `entrypoint/` | Root module called by the generated config. Configures the Proxmox provider from `TF_VAR_*` and delegates to `node/`. |
| `node/` | Orchestrates the four modules below. Derives cache-manifest and OEM-metadata paths from the explicit artifacts root. |
| `secrets/` | Pass-through of pre-resolved values. No resources, no providers. Presence is checked in the orchestrator before tofu runs. |
| `validate-spec/` | Normalizes single- and multi-node specs into a spec map; fails the plan on missing or unknown fields via lifecycle preconditions. |
| `render-manifest/` | Reads `manifest.json`, canonicalizes container images, and computes ignition variables and per-node networking. |
| `provision/` | Delegates in order: preflight → image-upload → ignition-config → vm-provision → firewall. |
| `provision/sub/image-upload/` | Uploads Flatcar and OEM images to Proxmox import storage. |
| `provision/sub/ignition-config/` | Renders the Butane template with `ct_config` and uploads it as a Proxmox snippet. |
| `provision/sub/vm-provision/` | Creates the VM: disks, network, GPU passthrough, initialization. |
| `provision/sub/firewall/` | Declarative `proxmox_virtual_environment_firewall_rules` only; receives no credentials. |

## Provider pinning / upgrades

All `required_providers` blocks pin exact versions; `versions.tf` is the canonical list
(bpg/proxmox 0.123.1, poseidon/ct 0.14.0, hashicorp/null 3.3.2, carlpett/sops 1.4.1) with the
upgrade procedure. Copy `.terraform.lock.hcl.example` into a workspace as `.terraform.lock.hcl` for
reproducible installs.
