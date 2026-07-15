# Apps

| App | Role |
| --- | --- |
| `node-a1` | application services |
| `node-gs` | game-server agents |
| `node-gw` | ZeroTier gateway |
| `node-infr` | CI, inference, runners |

Each app has a `Makefile`, `README.md`, `apps/<node>/` with `manifest.json`, `node-spec.json`, Butane
configs, and scripts, plus `variables/` and `secrets/README.md`.

From this directory: `make help`, `make validate`, `make <app>`, `make all`. Engine paths default to
`../../libs/modules/...` and can be overridden with `PXTH_COMMON_DIR`.

No secret material is included; runtime secrets use `/run/secrets/<name>.env`. See
`../examples/secrets/README.md`.
