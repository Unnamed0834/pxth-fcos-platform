"""Tests for the podman-secrets temp-file hardening (HIGH 5).

Podman and sudo are mocked; the tests verify that a unique 0600 mktemp file is
passed as an argv element, that no fixed /tmp filename is used, and that the
EXIT trap removes the file on success *and* on failure.
"""

import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

from testsupport import BASH, PODMAN_SECRETS



MOCK_PODMAN = r"""set -euo pipefail
out="${PODMAN_MOCK_OUT:?}"
tmpfile="${!#}"
if [[ "${PODMAN_MOCK_FAIL:-0}" != "0" ]]; then
    printf 'tmpfile=%s\n' "$tmpfile" > "$out"
    exit "$PODMAN_MOCK_FAIL"
fi
{
    # $0 is the script path (the stand-in for the podman binary itself).
    printf 'argc=%s\n' "$(( $# + 1 ))"
    printf 'argv=%s\n' "$0 $*"
    printf 'tmpfile=%s\n' "$tmpfile"
    printf 'mode=%s\n' "$(stat -c '%a' "$tmpfile")"
    printf 'content=%s\n' "$(cat "$tmpfile")"
} > "$out"
"""


class PodmanSecretsTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.secrets_dir = self.root / "secrets"
        self.secrets_dir.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.mock = self.bin / "podman"
        self.mock.write_text(f"#!{BASH}\n" + MOCK_PODMAN, encoding="utf-8")
        self.mock.chmod(0o755)
        self.out = self.root / "podman.out"

    def write_secret_file(self, name="token.env", value="token=s3cr3t-value"):
        path = self.secrets_dir / name
        path.write_text(value + "\n", encoding="utf-8")
        return path

    def run_create(self, secret_name="secret-uuid", basename="token", fail=None,
                   tmpdir=None):
        script = (
            "set -euo pipefail\n"
            f"source {shlex.quote(str(PODMAN_SECRETS))}\n"
            f"create {shlex.quote(secret_name)} {shlex.quote(basename)}\n"
            "printf 'trap_var=%s\\n' \"${_PXTH_SECRET_TMPFILE:-}\"\n"
        )
        env = dict(
            os.environ,
            PODMAN_SECRETS_DIR=str(self.secrets_dir),
            PODMAN_BIN=str(self.mock),
            PODMAN_SUDO="",
            PODMAN_MOCK_OUT=str(self.out),
            TMPDIR=str(tmpdir or self.root),
        )
        if fail is not None:
            env["PODMAN_MOCK_FAIL"] = str(fail)
        return subprocess.run(
            [BASH, "-c", script], env=env, capture_output=True, text=True
        )

    def parse_out(self):
        data = {}
        last_key = None
        for line in self.out.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                data[key] = value
                last_key = key
            elif last_key is not None:
                data[last_key] += "\n" + line
        return data


    def test_secure_temp_file_passed_as_argv_and_removed(self):
        self.write_secret_file()
        proc = self.run_create()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

        data = self.parse_out()
        self.assertEqual(data["argc"], "6")
        self.assertIn("secret create --replace secret-uuid", data["argv"])
        self.assertNotIn("sudo", data["argv"])
        self.assertEqual(data["mode"], "600")
        self.assertEqual(data["content"], "s3cr3t-value")

        tmpfile = Path(data["tmpfile"])
        self.assertEqual(tmpfile.parent, self.root)
        self.assertRegex(tmpfile.name, r"^pxth-secret\.[A-Za-z0-9]{8}$")
        self.assertFalse(tmpfile.exists(), "temp file was not removed")
        self.assertIn("trap_var=\n", proc.stdout)

    def test_temp_file_removed_when_podman_fails(self):
        self.write_secret_file()
        proc = self.run_create(fail=7)
        self.assertEqual(proc.returncode, 7, proc.stdout + proc.stderr)
        self.assertIn("podman secret create failed", proc.stderr)
        tmpfile = Path(self.parse_out()["tmpfile"])
        self.assertFalse(tmpfile.exists(), "temp file leaked after podman failure")

    def test_temp_files_are_unique_per_call(self):
        self.write_secret_file()
        first = self.run_create(secret_name="secret-one")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        first_path = self.parse_out()["tmpfile"]

        second = self.run_create(secret_name="secret-two")
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        second_path = self.parse_out()["tmpfile"]

        self.assertNotEqual(first_path, second_path)
        self.assertFalse(Path(first_path).exists())
        self.assertFalse(Path(second_path).exists())

    def test_missing_secret_file_fails(self):
        proc = self.run_create(basename="does-not-exist")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("missing or unreadable", proc.stderr)
        self.assertFalse(self.out.exists())

    def test_path_traversal_in_basename_is_rejected(self):
        proc = self.run_create(basename="../../etc/passwd")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("invalid secret file basename", proc.stderr)

    def test_path_traversal_in_secret_name_is_rejected(self):
        proc = self.run_create(secret_name="bad;name")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("invalid secret name", proc.stderr)

    def test_multiline_value_is_preserved(self):
        self.write_secret_file(value="token=first\nsecond")
        proc = self.run_create()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(self.parse_out()["content"], "first\nsecond")


if __name__ == "__main__":
    unittest.main()
