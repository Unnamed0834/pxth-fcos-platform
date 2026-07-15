"""Tests for the SOPS pre-commit hook (HIGH 4).

The hook is exercised as a subprocess with a mock ``sops`` on PATH and a
temporary HOOK_REPO_ROOT, so no real age keys or secrets are involved.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from testsupport import BASH, HOOK, encrypted_yaml





MOCK_SOPS = r"""set -euo pipefail
if [[ "${1:-}" != "-d" ]]; then
    echo "mock sops: only -d is supported" >&2
    exit 3
fi
file="${2:-}"
case "$(basename "$file")" in
    undecryptable.yaml)
        echo "mock: no matching age identity" >&2
        exit 2
        ;;
    empty.yaml)
        exit 0
        ;;
    double.yaml)
        printf '%s\n' 'token: ENC[AES256_GCM,data:deadbeef,iv:aa,tag:bb,type:str]'
        exit 0
        ;;
    *)
        sed -n '/^sops:/q; p' "$file"
        exit 0
        ;;
esac
"""


class SopsHookTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.secrets = self.root / "secrets"
        self.bin = self.root / "bin"

    def write_secret(self, name, content):
        self.secrets.mkdir(parents=True, exist_ok=True)
        path = self.secrets / name
        path.write_text(content, encoding="utf-8")
        return path

    def install_mock_sops(self, script=MOCK_SOPS):
        self.bin.mkdir(parents=True, exist_ok=True)
        mock = self.bin / "sops"
        mock.write_text(f"#!{BASH}\n" + script, encoding="utf-8")
        mock.chmod(0o755)

    def run_hook(self, with_mock=True, path_override=None, extra_env=None):
        if with_mock:
            self.install_mock_sops()
        env = dict(os.environ, HOOK_REPO_ROOT=str(self.root))
        if with_mock:
            env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        if path_override is not None:
            env["PATH"] = path_override
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [BASH, str(HOOK)], env=env, capture_output=True, text=True
        )


    def test_no_secrets_dir_passes(self):
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("no secrets/", proc.stdout)

    def test_properly_encrypted_file_passes(self):
        self.write_secret("token.yml", encrypted_yaml("token: placeholder"))
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("SOPS metadata, recipients and decryption verified", proc.stdout)

    def test_plaintext_file_fails(self):
        self.write_secret("plain.yml", "token: plaintext\n")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("unencrypted secret", proc.stdout)
        self.assertIn("plain.yml", proc.stdout)

    def test_markdown_documentation_is_skipped(self):



        self.write_secret("README.md", "# Secret model\nEverything is out of band.\n")
        nested = self.secrets / "nested"
        nested.mkdir()
        (nested / "NOTES.MD").write_text("# Notes\nNo SOPS metadata here.\n", encoding="utf-8")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("SKIP: documentation file: secrets/README.md", proc.stdout)
        self.assertIn("SKIP: documentation file: secrets/nested/NOTES.MD", proc.stdout)
        self.assertNotIn("ERROR:", proc.stdout)

    def test_non_markdown_plaintext_still_fails_with_docs_present(self):
        self.write_secret("README.md", "# Secret model\nOut of band.\n")
        self.write_secret("plain.yml", "token: plaintext\n")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("unencrypted secret", proc.stdout)
        self.assertIn("secrets/plain.yml", proc.stdout)
        for line in proc.stdout.splitlines():
            if "README.md" in line:
                self.assertTrue(line.startswith("SKIP:"), line)

    def test_dummy_sops_key_without_age_recipient_fails(self):


        self.write_secret("dummy.yml", "token: plaintext\nsops: {}\n")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no SOPS block with age recipients", proc.stdout)

    def test_enc_filename_is_not_exempt(self):

        self.write_secret("leak.enc.yml", "token: plaintext\n")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("unencrypted secret", proc.stdout)

    def test_decryption_failure_is_fatal(self):
        self.write_secret("undecryptable.yaml", encrypted_yaml())
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("SOPS decryption failed", proc.stdout)

    def test_double_encrypted_file_fails(self):
        self.write_secret("double.yaml", encrypted_yaml())
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("still contains SOPS ciphertext", proc.stdout)

    def test_empty_decryption_fails(self):
        self.write_secret("empty.yaml", encrypted_yaml())
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("empty content", proc.stdout)

    def test_one_bad_file_fails_whole_hook(self):
        self.write_secret("good.yml", encrypted_yaml())
        self.write_secret("bad.yml", "token: plaintext\n")
        proc = self.run_hook()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("1 check(s) failed", proc.stdout)
        self.assertIn("good.yml", proc.stdout)

    def test_missing_sops_binary_is_fatal(self):

        restricted = self.root / "restricted-bin"
        restricted.mkdir()
        for tool in ("bash", "dirname", "find", "grep", "awk", "cat", "basename"):
            source = shutil.which(tool)
            if source:
                (restricted / tool).symlink_to(source)
        self.write_secret("token.yml", encrypted_yaml())
        proc = self.run_hook(with_mock=False, path_override=str(restricted))
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("sops is not installed", proc.stdout)


if __name__ == "__main__":
    unittest.main()
