"""Unit tests for libs/scripts/ci/validate-images.py.

Covers the no-op regression (HIGH 8) plus a positive case and every negative
case the validator is required to detect.
"""

import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


from testsupport import (
    DOC_IP_1,
    DOC_IP_2,
    VALIDATE_IMAGES,
    load_module,
    valid_artifact,
    valid_manifest,
    valid_spec,
    write_json,
)

vi = load_module("validate_images", VALIDATE_IMAGES)


class ValidateImagesTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.apps = Path(self._tmp.name) / "apps"

    def add_node(self, node="node1", group="group1", manifest=None, spec=None,
                 layout="monorepo"):
        parent = self.apps / group / "apps" if layout == "monorepo" else self.apps
        node_dir = parent / node
        node_dir.mkdir(parents=True, exist_ok=True)
        write_json(
            node_dir / "manifest.json",
            valid_manifest(node) if manifest is None else manifest,
        )
        if spec is not False:
            write_json(
                node_dir / "node-spec.json",
                valid_spec(node) if spec is None else spec,
            )
        return node_dir

    def errors(self):
        return [message for result in vi.collect_results(self.apps)
                for message in result.errors]

    def error_text(self):
        return "\n".join(self.errors())




    def test_valid_monorepo_manifest_passes(self):
        self.add_node()
        self.assertEqual(self.errors(), [])
        stream = io.StringIO()
        self.assertEqual(vi.run_validation(self.apps, stream=stream), 0)
        self.assertIn("PASS: All container images and wiring validated", stream.getvalue())

    def test_valid_single_level_layout_is_discovered(self):
        self.add_node(node="node1", layout="flat")
        self.assertEqual(len(vi.discover_manifests(self.apps)), 1)
        self.assertEqual(self.errors(), [])

    def test_signed_digest_pair_without_digest_is_accepted(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"].pop("digest")
        manifest["artifacts"]["base"].update({
            "digests_url": "https://example.com/artifacts/SHA256SUMS",
            "digests_asc": "https://example.com/artifacts/SHA256SUMS.asc",
        })
        self.add_node(manifest=manifest)
        self.assertEqual(self.errors(), [])




    def test_missing_min_size_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"].pop("min_size")
        self.add_node(manifest=manifest)
        self.assertIn("min_size", self.error_text())

    def test_zero_min_size_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"]["min_size"] = 0
        self.add_node(manifest=manifest)
        self.assertIn("invalid min_size", self.error_text())

    def test_boolean_min_size_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"]["min_size"] = True
        self.add_node(manifest=manifest)
        self.assertIn("invalid min_size", self.error_text())




    def test_missing_digest_and_signed_pair_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"].pop("digest")
        self.add_node(manifest=manifest)
        self.assertIn("neither a valid 'digest'", self.error_text())

    def test_malformed_digest_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"]["digest"] = "not-a-hex-digest"
        self.add_node(manifest=manifest)
        self.assertIn("malformed 'digest'", self.error_text())

    def test_partial_signed_pair_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["base"].pop("digest")
        manifest["artifacts"]["base"]["digests_url"] = "https://example.com/SHA256SUMS"
        self.add_node(manifest=manifest)
        self.assertIn("incomplete signed digest pair", self.error_text())




    def test_container_requires_explicit_digest(self):
        manifest = valid_manifest()
        manifest["artifacts"]["app"].pop("digest")
        manifest["artifacts"]["app"].update({
            "digests_url": "https://example.com/SHA256SUMS",
            "digests_asc": "https://example.com/SHA256SUMS.asc",
        })
        self.add_node(manifest=manifest)
        self.assertIn("must pin an explicit image 'digest'", self.error_text())

    def test_container_without_image_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["app"].pop("image")
        self.add_node(manifest=manifest)
        self.assertIn("has no image reference", self.error_text())

    def test_container_dest_wiring_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["app"]["dest"] = "bin/app"
        self.add_node(manifest=manifest)
        self.assertIn("containers/...tar", self.error_text())




    def test_bundle_container_missing_from_artifacts_fails(self):
        manifest = valid_manifest()
        manifest["oem"]["bundle"]["containers"].append("ghost")
        self.add_node(manifest=manifest)
        self.assertIn("not declared in 'artifacts'", self.error_text())

    def test_bundle_container_wrong_type_fails(self):
        manifest = valid_manifest()

        manifest["oem"]["bundle"]["containers"] = ["base"]
        self.add_node(manifest=manifest)
        self.assertIn("not a container/build artifact", self.error_text())




    def test_duplicate_dest_fails(self):
        manifest = valid_manifest()
        manifest["artifacts"]["other"] = valid_artifact(
            dest=manifest["artifacts"]["base"]["dest"]
        )
        self.add_node(manifest=manifest)
        self.assertIn("duplicate destination", self.error_text())

    def test_invalid_json_is_reported(self):
        node_dir = self.add_node()
        (node_dir / "manifest.json").write_text("{ not json", encoding="utf-8")
        self.assertIn("Invalid JSON", self.error_text())

    def test_no_manifests_is_reported(self):
        self.assertEqual(vi.run_validation(self.apps, stream=io.StringIO()), 1)
        self.assertIn("No manifests found", self.error_text())




    def test_duplicate_ip_fails(self):
        self.add_node(node="node1")
        self.add_node(node="node2", spec=valid_spec("node2", 1002, DOC_IP_1, 100))
        self.assertIn("IP conflict", self.error_text())

    def test_duplicate_vmid_fails(self):
        self.add_node(node="node1")
        self.add_node(node="node2", spec=valid_spec("node2", 1001, DOC_IP_2, 200))
        self.assertIn("VM ID conflict", self.error_text())

    def test_duplicate_host_port_on_same_ip_fails(self):
        spec1 = valid_spec("node1")
        spec1["services"] = {"web": {"ports": [{"host_port": 8080}]}}
        spec2 = valid_spec("node2", 1002, DOC_IP_1, 100)
        spec2["services"] = {"web": {"ports": [{"host_port": 8080}]}}
        self.add_node(node="node1", spec=spec1)
        self.add_node(node="node2", spec=spec2)
        self.assertIn("port conflict", self.error_text())

    def test_subnet_with_multiple_vlans_fails(self):
        self.add_node(node="node1")

        self.add_node(node="node2", spec=valid_spec("node2", 1002, "192.0.2.20/24", 200))
        self.assertIn("VLAN conflict", self.error_text())




    def test_cli_apps_dir_argument_exit_codes(self):
        self.add_node()
        proc = subprocess.run(
            [sys.executable, str(VALIDATE_IMAGES), "--apps-dir", str(self.apps)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("PASS:", proc.stdout)

    def test_cli_env_var_and_failure(self):
        self.add_node()
        env = dict(os.environ, APPS_DIR=str(self.apps))
        proc = subprocess.run(
            [sys.executable, str(VALIDATE_IMAGES)],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

        manifest = valid_manifest()
        manifest["artifacts"]["base"].pop("digest")
        del manifest["artifacts"]["app"]
        manifest.pop("oem")
        self.add_node(node="node2", manifest=manifest,
                      spec=valid_spec("node2", 1002, DOC_IP_2, 200))
        proc = subprocess.run(
            [sys.executable, str(VALIDATE_IMAGES)],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL:", proc.stdout)
        self.assertIn("neither a valid 'digest'", proc.stdout)

    def test_discovery_supports_both_layouts_at_once(self):
        self.add_node(node="node1", layout="monorepo")
        self.add_node(node="node2", layout="flat")
        names = {node for node, _, _ in vi.discover_manifests(self.apps)}
        self.assertEqual(names, {"node1", "node2"})


if __name__ == "__main__":
    unittest.main()
