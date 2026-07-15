# node-gw1 — ZeroTier Gateway

ZeroTier L3 gateway VM bridging the ZeroTier overlay network to VLAN 1002, using native ZeroTier
binaries and restic backups to S3.

## Node

| Node | Role | VM ID | IP | vCPU | RAM | Disk | VLAN |
| --- | --- | --- | --- | --- | --- | --- | --- |
| node-gw1 | ZeroTier gateway | 2006 | 203.0.113.20 | 2 | 2 GB | 50 GB | 1002 |

## Topology

```
VLAN 1002 — 203.0.113.0/24 (node_net)
                 node-gw1 (203.0.113.20)
                 Flatcar + native binaries
                 ├─ ZeroTier One (network 0000000000000000)
                 └─ Restic daily backups to S3
                        │ L3 routing, no NAT
                 ZeroTier overlay network
```

## Pipeline

`Cache → Pack → Deploy`

```sh
make node-gw1
make node-gw1-cache
make node-gw1-pack
make node-gw1-vm
```

`PXTH_COMMON_DIR` defaults to `../..`.

## Services

- IP: 203.0.113.20, VLAN 1002 (node_net); OS: Flatcar Container Linux, immutable rootfs
- Runtime: native ZeroTier binaries (v1.16.2 from the .deb package)
- ZeroTier One systemd service, joined to network `0000000000000000`
- Restic daily backups to S3 at `00:42` with a weekly health check
- L3 routing between the ZeroTier overlay and VLAN 1002; no NAT or proxy ARP

## Backups

`/var/lib/zerotier-one` — ZeroTier identity and network configuration, persisted across reboots.

## Files

```
apps/node-gw/
├── apps/node-gw1/{manifest.json,node-spec.json,node-gw1-config.bu,
│                 scripts/{node-gw1-setup.sh,secrets-create.sh,zt-routing-setup.sh}}
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
OEM disk extract → ZeroTier binaries install → Backup restore → SELinux setup
    → nftables egress → ZeroTier start → Routing setup → Services start
```

1. OEM disk extract — SHA256 verify and extract bundle
2. ZeroTier binaries install — `zerotier-one` and `zerotier-cli` to `/opt/bin`
3. Backup restore — ZeroTier identity from restic, before ZeroTier starts
4. SELinux setup — enforcing mode
5. nftables egress — outbound filtering
6. ZeroTier One — start service, join network `0000000000000000`
7. Routing setup — L3 forwarding between the overlay and VLAN 1002
8. Services start — backup timer and health check

## Routing settings

- IP forwarding enabled (`net.ipv4.ip_forward=1`)
- ZeroTier: `allowManaged=1`, `allowDefault=0`
- iptables FORWARD limited to the ZeroTier interface and eth0 (VLAN 1002)
- No NAT or masquerade; MTU 1500 on the ZeroTier interface with PMTUD enabled

## Security settings

- Digests and signatures verified before caching; OEM disk verified with SHA256 at boot
- SELinux enforcing; nftables outbound filtering for root and zerotier UIDs
- ZeroTier overlay and VLAN 1002 kept separate; no cross-traffic
- Runtime secrets from `/run/secrets/`; none baked into images
- Key-only SSH, no root login
