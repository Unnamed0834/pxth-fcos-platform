# pxth-cache

Downloads and verifies artifacts declared in `manifest.json`, then writes versioned cache paths and
`.cache-manifest.json`.

## CLI

`nodes` · `path <node>` · `sync <node> [force]` · `verify <node>` · `status <node>`

## Verification

- Signature failure is fatal. Full fingerprint pin, no runtime key download, SHA-256 minimum.
- Hashes come from GPG-verified cleartext, not the downloaded `.DIGESTS`.
- Every artifact is re-hashed during verification.
- Cache manifest has an HMAC-SHA256 sidecar keyed by `PXTH_CACHE_HMAC_KEY` or
  `/run/secrets/pxth-cache-hmac.env`.
- Unsigned, tampered, or missing state exits non-zero.

## Keys and credentials

Public keys live in `lib/gpg/` and must be pre-provisioned. S3 credentials come from the environment
or `/run/secrets/*.env`, never from `source` or `eval`.
