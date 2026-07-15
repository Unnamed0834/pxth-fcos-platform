# pxth fcOS Platform

Flatcar Container Linux (fcOS) VMs on Proxmox VE, provisioned from declarative manifests with OpenTofu.

## Layout

```
libs/modules/    cache, pack, deploy, tofu
libs/scripts/    CI hooks, image validation, shared helpers
apps/            node-a1, node-gs, node-gw, node-infr
docs/            node and application overview
examples/        placeholder secret shapes
tests/           validation unit tests
tools/           repository checks
```

The node and application sets are listed in [docs/nodes.md](docs/nodes.md). This
generation has no bastion host; deploys run from an operator workstation.

## Commands

```sh
make verify
make test
make validate
make app-validate
```

`pack` requires `PXTH_CACHE_HMAC_KEY` or `/run/secrets/pxth-cache-hmac.env`. Runtime secrets use
`/run/secrets/<name>.env`; artifact digests and signing-key paths are placeholders.

License: MIT.

## Provisioning flow

`manifest + node-spec → cache → pack → deploy → tofu → Flatcar VM`

| Stage | Reads | Produces | Failure |
|-------|-------|----------|---------|
| cache | `manifest.json` | verified artifacts | stops on failed digest or signature check |
| pack | verified artifacts | OEM disk image | requires a valid cache manifest |
| deploy | `node-spec.json`, `variables/`, `/run/secrets` | tofu inputs | stops on missing values |
| tofu | VM spec, disk image | Proxmox VM | plan, then apply |
| boot | Ignition | configured Flatcar VM | — |
