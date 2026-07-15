# Secrets

This directory contains no secret material. The former SOPS-encrypted files and `.sops.yaml` were
removed.

Runtime secrets are expected at `/run/secrets/<name>.env` on each node, supplied out of band. The
naming convention and operator checklist are in
[examples/secrets/README.md](../../../examples/secrets/README.md).
