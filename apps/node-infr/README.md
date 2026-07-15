# node-infr — Core Infrastructure

Infrastructure nodes for CI, GPU inference, and runners.

## Nodes

| Node | Role | VM ID | IP | vCPU | RAM | Disk | VLAN |
| --- | --- | --- | --- | --- | --- | --- | --- |
| node-f1 | CI/CD seed (Forgejo, Zot, Caddy) | 2001 | 198.51.100.21 | 4 | 8 GB | 750 GB | 1001 |
| node-g1 | GPU inference (llama.cpp, vLLM) | 2002 | 198.51.100.51 | 16 | 64 GB | 100 GB | 1001 |
| node-r | CI/CD runners (r1, r2, r3) | 2003–05 | 198.51.100.31–33 | 2 each | 4 GB each | 50 GB each | 1001 |

## Topology

```
Proxmox VE cluster
├── node-f1 — Forgejo, PostgreSQL, Zot, Caddy, restic
├── node-g1 — llama.cpp / vLLM, 4 GPUs, containerd
└── node-r — node-r1, node-r2, node-r3

External dependencies
├── NFS server — model weights
├── S3 storage — tfstate, backups, registry
└── Cloudflare DNS — TLS certificates
```

## Pipeline

`Cache → Pack → Deploy`

```sh
make node-f1
make node-g1
make node-r

make node-f1-cache
make node-f1-pack
make node-f1-vm

make validate
make validate-images
```

`PXTH_COMMON_DIR` defaults to `../..`. `INFERENCE_ENGINE` selects the active container
(default: `llama-server`).

## Files

```
apps/node-infr/
├── apps/node-f1/{manifest.json,node-spec.json,node-f1-config.bu,scripts/node-f1-setup.sh}
├── apps/node-g1/{manifest.json,node-spec.json,node-g1-config.bu,
│                 scripts/{node-g1-setup.sh,node-g1-workload.sh}}
├── apps/node-r/{manifest.json,node-spec.json,node-r-config.bu,
│                scripts/{node-r-config.yaml.tmpl,node-r-setup.sh}}
├── secrets/README.md
└── variables/
    ├── shared/{pve.yml,storage/s3-state-region.yml,tofu/plugin-cache-path.yml,tofu/ssh-public-key.yml}
    └── infr-r/shared/runner_server_url.yml
```

## Secrets and variables

Runtime secrets are read at boot from `/run/secrets/<name>.env`; missing files fail closed. See
`secrets/README.md` and `../../examples/secrets/`.

| Category | Source | Used by | Resolved at |
| --- | --- | --- | --- |
| Shared variables | `variables/shared/*.yml` | OpenTofu, all nodes | Deploy time |
| Node variables | `variables/<node>/*.yml` | OpenTofu, that node | Deploy time |

`pxth-deploy` reads `variables/shared/` first, then `variables/<node>/`; node-specific keys
override shared keys. The result is a JSON map passed to OpenTofu as `resolved_variables`.

## Boot sequence

```
OEM disk extract → Sysexts install → SELinux setup → Podman/containerd enable
    → Load containers → Node setup script → Services start
```

1. OEM disk extract — SHA256 verify and extract bundle
2. Sysexts install — podman/NVIDIA sysext
3. SELinux setup — enforcing mode
4. Podman/containerd — rootless environment
5. Load containers — pre-bake images
6. Node setup — run once, guarded by a sentinel
7. Services start — Forgejo, Zot, Caddy, runners, workload

## Node details

### node-f1

Runs Forgejo, PostgreSQL, Zot, Caddy, and restic.

- Forgejo: `codeberg.org/forgejo/forgejo:15.0.3-rootless`, with S3 LFS and attachments
- Zot: `ghcr.io/project-zot/zot-linux-amd64:v2.1.17`, with cicd and dev auth profiles
- Caddy: Cloudflare DNS-01 challenge for Let's Encrypt TLS (custom xcaddy build)
- PostgreSQL: `postgres:17.10`
- Backups: daily restic to S3; reprovision requires a backup within 48h (`FORCE=1` bypasses it)

### node-g1

GPU inference node with 4 GPUs; llama.cpp or vLLM run under containerd.

- NVIDIA driver sysext 570.181 and runtime sysext from Flatcar
- Models: GGUF files from NFS at `198.51.100.10:/mnt/storage/private/assets/gguf`
- Workloads managed by `node-g1-workload.sh`:
  - T4 (default): Qwen3.5-122B-A10B across all four GPUs, tensor parallel, port 8000
  - T2: Qwen3.6-35B-A3B-MTP, two instances across GPUs 0–1 (port 8000) and 2–3 (port 8001)
- Power limit: 160 W per GPU with nvidia-persistenced

### node-r

Three runner nodes, each running one Forgejo runner container.

- Images: `code.forgejo.org/forgejo/runner:12.11.0`, `ubuntu:24.04`
- Runner UUID and token supplied through Podman secrets, not stored on disk
- `node-r-config.yaml.tmpl` is assembled at boot from the OEM template and environment variables
  (runner name, server URL, UUID, token)
- Network: inbound SSH, outbound HTTP/HTTPS, access to node-f1 on ports 80, 443, 2222
- Egress: nftables allows only SSH (22), HTTP (80), HTTPS (443), and DNS (53/udp)

## Security settings

- Digests and signatures verified before caching; OEM disk verified with SHA256 at boot
- SELinux enforcing; rootless Podman as UID 5000 with user namespace remapping
- Distinct host UIDs per container role (postgres=100998, forgejo=100999, zot=101000, caddy=101001)
- Frontend and application networks; outbound nftables filtering per node
- Runtime secrets from `/run/secrets/`; none baked into images
- Key-only SSH, no root login
