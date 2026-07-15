# node-gs — Game Server Nodes

Three Flatcar VMs with rootless Podman, each running an Arcane headless agent managed from node-a1.

## Nodes

| Node | Role | VM ID | IP | vCPU | RAM | Disk | VLAN |
| --- | --- | --- | --- | --- | --- | --- | --- |
| node-gs1 | Game server agent | 2008 | 203.0.113.31 | 6 | 12 GB | 100 GB | 1002 |
| node-gs2 | Game server agent | 2009 | 203.0.113.32 | 6 | 12 GB | 100 GB | 1002 |
| node-gs3 | Game server agent | 2010 | 203.0.113.33 | 6 | 12 GB | 100 GB | 1002 |

## Topology

```
VLAN 1002 — 203.0.113.0/24 (node_net)
     node-gs1 203.0.113.31   node-gs2 203.0.113.32   node-gs3 203.0.113.33
     Flatcar + Podman        Flatcar + Podman        Flatcar + Podman
     └─ arcane-edge agent    └─ arcane-edge agent    └─ arcane-edge agent

     Arcane manager on node-a1 (203.0.113.21) manages all three agents.
```

## Pipeline

`Cache → Pack → Deploy`

```sh
export PXTH_COMMON_DIR=$(pwd)/../..
export APPS_DIR=$(pwd)/apps
export REPO_ROOT=$(pwd)

../../libs/modules/cache/cache.sh sync node-gs
../../libs/modules/pack/pack.sh pack node-gs
../../libs/modules/deploy/deploy.sh deploy node-gs
```

`PXTH_COMMON_DIR` defaults to `../..`.

## Services

- IPs: 203.0.113.31–33, VLAN 1002 (node_net); OS: Flatcar Container Linux, immutable rootfs
- Runtime: rootless Podman as UID 5000
- arcane-headless in Edge mode: outbound connection to the Arcane manager on node-a1
  - `EDGE_AGENT=true`, `EDGE_TRANSPORT=auto`
  - Mounts the host Podman socket at `/run/user/5000/podman/podman.sock`
- Restic daily backups to S3 at `00:42` with a weekly health check

## Backups

Paths:

- `/home/containers/volumes/agent-data` — Arcane agent data
- `/home/containers/.local/share/containers/storage/volumes` — Podman volumes
- `/home/containers/.config/containers` — Podman container config

## Files

```
apps/node-gs/
├── apps/node-gs/{manifest.json,node-spec.json,node-gs-config.bu,
│                 scripts/node-gs-setup.sh,scripts/lib/logging.sh}
├── secrets/README.md
└── variables/shared/{pve.yml,storage/s3-state-region.yml,tofu/plugin-cache-path.yml,tofu/ssh-public-key.yml}
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

## Validation

```sh
APPS_DIR=$(pwd)/apps python3 $(PXTH_COMMON_DIR)/libs/scripts/ci/validate-images.py
```

## Boot sequence

```
OEM disk extract → Sysexts install → SELinux setup → Podman enable
    → Load containers → Secrets create → Backup restore → Services start
```

1. OEM disk extract — SHA256 verify and extract bundle
2. Sysexts install — podman sysext
3. SELinux setup — enforcing mode
4. Podman — rootless environment
5. Load containers — pre-bake the arcane-headless image
6. Secrets create — Arcane agent token as a Podman secret
7. Backup restore — restore from restic when available
8. Services start — arcane-edge-agent

## Security settings

- Digests and signatures verified before caching; OEM disk verified with SHA256 at boot
- SELinux enforcing; rootless Podman as UID 5000 with distinct host UIDs per container role
- Frontend and backend internal networks; outbound nftables filtering per UID
- Runtime secrets from `/run/secrets/`; none baked into images
- Key-only SSH, no root login
