# node-a1 — Application Services

Runs Caddy, Arcane, Sharkord, Filegator, and Jellyfin on a Flatcar VM with rootless Podman.

## Node

| Node | Role | VM ID | IP | vCPU | RAM | Disk | VLAN |
| --- | --- | --- | --- | --- | --- | --- | --- |
| node-a1 | Application services | 2007 | 203.0.113.21 | 6 | 12 GB | 100 GB | 1002 |

## Topology

```
VLAN 1002 — 203.0.113.0/24 (node_net)
                       node-a1 (203.0.113.21)
                       Flatcar + Podman
                       ├─ Caddy (80/443)
                       ├─ Arcane (3552)
                       ├─ Sharkord (4991 internal, 40000 external)
                       ├─ Filegator (8080 internal)
                       └─ Jellyfin (8096 internal)
```

## Pipeline

`Cache → Pack → Deploy`

```sh
export PXTH_COMMON_DIR=$(pwd)/../..
export APPS_DIR=$(pwd)/apps
export REPO_ROOT=$(pwd)

../../libs/modules/cache/cache.sh sync node-a1
../../libs/modules/pack/pack.sh pack node-a1
../../libs/modules/deploy/deploy.sh deploy node-a1
```

`PXTH_COMMON_DIR` defaults to `../..`.

## Services

- IP: 203.0.113.21, VLAN 1002 (node_net); OS: Flatcar Container Linux, immutable rootfs
- Runtime: rootless Podman as UID 5000
- Caddy (80/443) — TLS termination for `*.int.example.com`
- Arcane (3552 internal) — `arcane.example.com`
- Sharkord (4991 internal, 40000 external) — `chat.example.com`, `rtc.example.com`
- Filegator (8080 internal) — `files.example.com`
- Jellyfin (8096 internal) — `media.example.com`

## Backups

Daily restic to S3 (`node-a1/restic-node-a1`). Paths:

- `/home/containers/volumes/arcane-data` — Arcane SQLite database
- `/home/containers/volumes/caddy-data`, `caddy-config` — Caddy certificates and config
- `/home/containers/volumes/sharkord-data` — Sharkord data
- `/home/containers/volumes/filegator-private` — Filegator files
- `/home/containers/volumes/jellyfin-config`, `jellyfin-cache` — Jellyfin config and cache
- `/home/containers/.config/containers` — Podman container config

## Files

```
apps/node-a1/
├── apps/node-a1/{manifest.json,node-spec.json,node-a1-config.bu,scripts/node-a1-setup.sh}
├── secrets/README.md
└── variables/
    ├── shared/{pve.yml,storage/s3-state-region.yml,tofu/plugin-cache-path.yml,tofu/ssh-public-key.yml}
    └── node-a1/{network_subnet.yml,nfs.yml,zerotier_gateway.yml}
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
    → Load containers → Node setup script → Services start
```

1. OEM disk extract — SHA256 verify and extract bundle
2. Sysexts install — podman sysext
3. SELinux setup — enforcing mode
4. Podman — rootless environment
5. Load containers — pre-bake images
6. Node setup — run once, guarded by a sentinel
7. Services start — Caddy, Arcane, Sharkord, Filegator, Jellyfin

## Security settings

- Digests and signatures verified before caching; OEM disk verified with SHA256 at boot
- SELinux enforcing; rootless Podman as UID 5000 with distinct host UIDs per container role
- Frontend and backend internal networks; outbound nftables filtering per UID
- Runtime secrets from `/run/secrets/`; none baked into images
- Key-only SSH, no root login
