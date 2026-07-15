# pxth-deploy

CLI: `deploy.sh nodes` and `deploy.sh deploy <node>`.

## Deploy contract

- Secrets are not accepted on the command line or stored in plaintext files. `engine.sh` checks that
  required secrets are present before OpenTofu runs. Scalars are passed as `TF_VAR_*` environment
  variables; maps go in a `mktemp`-created `0600` `.tfvars.json` passed with `-var-file`. Backend
  credentials use `AWS_*` environment variables; only non-secret values appear in quoted
  `-backend-config` arguments. A single `EXIT` trap in `lib/workspace.sh` removes temp files.
- Teardown requires `DESTROY=1` and `DESTROY_CONFIRM=yes`; a normal deploy only plans and applies.
- `PLAN_ONLY=1` saves a plan to the work directory and exits without applying. Normal deploys apply
  that saved plan.
- Shell entrypoints use `set -euo pipefail`, quoted variables, no `eval`, and `mktemp` with `trap`
  for every temporary file.
- Absolute artifact paths are injected into `resolved_variables` so modules do not derive paths from
  the temporary `path.module` copy.

See `../tofu/README.md` for the tofu-side contract and pinned versions.
