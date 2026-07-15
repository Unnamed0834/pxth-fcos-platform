# pxth-pack

Builds the OEM disk bundle from verified cache artifacts.

## CLI

`nodes` · `path <node>` · `pack <node>` · `status <node>`

## Contract

- Requires a valid `.cache-manifest.json` with a verified HMAC sidecar. Missing or tampered state fails.
- Re-hashes artifacts. Never writes back to `manifest.json`.
- Reads and writes no secrets; `pack-bundle.py` refuses secret paths.
- Helper arguments pass through argv, never interpolated into `python3 -c`.
- Output: `upload/<prefix>_oem_disk.raw`, `upload/<prefix>_flatcar_production_proxmoxve_image.qcow2`,
  `upload/oem-metadata.json`.
