# Tests

Tests for `libs/scripts/` need Python 3 and Bash only. Mock `sops` and `podman` binaries are created
at runtime; no network access or credentials are used.

## Running

```sh
python3 -m pytest tests -q
python3 -m unittest discover -s tests -q
```

Run from the repository root; `testsupport.py` resolves paths relative to itself.

## Layout

| File | Covers |
| --- | --- |
| `testsupport.py` | Path setup, importlib loader for hyphenated script filenames, fixture builders |
| `test_validate_images.py` | Image and wiring validator: min_size, digest/signed pair, container digest wiring, bundle containers, cross-node IP/VMID/VLAN/port conflicts, JSON errors, CLI exit codes, both manifest layouts |
| `test_sops_hook.py` | SOPS hook: real SOPS block with age recipients, fatal decryption failures, no ciphertext after decryption, no `*.enc.*` exemption, dummy `sops:` key rejected, missing `sops` binary, `*.md` documentation skipped while non-`.md` plaintext still fails |
| `test_podman_secrets.py` | Podman staging: `mktemp` path, mode 0600, argv passing, no sudo when disabled, EXIT trap cleanup on success and podman failure, unique temp files, input validation |

## Conventions

- Fixtures use `tempfile.TemporaryDirectory()` with `addCleanup`, `mktemp` where shell is involved,
  and mocked external commands via a temporary PATH.
- Example values use `example.com`, documentation IP ranges, and placeholder secrets.
- Tests invoke scripts as subprocesses where exit codes and argv matter, and call pure functions
  directly through `testsupport.load_module()`.
