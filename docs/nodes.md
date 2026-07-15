# Nodes

These examples predate a bastion host. There is no central jump or deploy node:
the operator runs cache, pack, and deploy from a workstation against the
Proxmox API, and each VM accepts SSH from scoped keys.

## Applications and nodes

| App | Node | Role | Application set |
|-----|------|------|-----------------|
| node-a1 | node-a1 | application services | Caddy, Arcane, Sharkord, Filegator, Jellyfin |
| node-gs | node-gs1, node-gs2, node-gs3 | game servers | Arcane headless agents |
| node-gw | node-gw1 | network | ZeroTier L3 gateway, restic |
| node-infr | node-f1 | infrastructure | Forgejo, PostgreSQL, Zot, Caddy |
| node-infr | node-g1 | inference | llama.cpp, vLLM |
| node-infr | node-r1, node-r2, node-r3 | runners | Forgejo runners |

## Handoff

Each app directory declares what to deploy:

| File | Contents |
|------|----------|
| `apps/<node>/manifest.json` | artifacts, digests, and OEM bundle contents |
| `apps/<node>/node-spec.json` | VM id, VLAN, address, resources, firewall rules |
| `variables/` | non-secret values |
| `secrets/` | no material in this repository; runtime values use `/run/secrets/<name>.env` |

The engine under `libs/modules/` consumes those files in four stages:

1. `pxth-cache` downloads and verifies artifacts against declared digests.
2. `pxth-pack` builds an OEM disk bundle from verified artifacts.
3. `pxth-deploy` resolves values and drives OpenTofu.
4. `pxth-tofu` creates the VM; Butane and Ignition configure Flatcar at boot.

Each app `README.md` lists its node table, addresses, and port layout.
