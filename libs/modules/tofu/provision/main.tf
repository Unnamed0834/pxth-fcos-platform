































terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.123.1"
    }
    ct = {
      source  = "poseidon/ct"
      version = "= 0.14.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.3.2"
    }
  }
}





resource "null_resource" "preflight" {
  triggers = {
    node_name       = var.node_name
    vm_id           = var.spec.vm_id
    ignition_exists = fileexists(var.ignition_path) ? "true" : "false"
    artifacts_dir   = var.artifacts_dir
    cache_manifest  = var.cache_manifest_path != "" ? fileexists(var.cache_manifest_path) ? "true" : "false" : "skipped"
    manifest_path   = var.manifest_path
  }

  provisioner "local-exec" {

    interpreter = ["bash", "-euo", "pipefail", "-c"]
    command     = <<EOF
      echo "=== Pre-flight checks for ${var.node_name} ==="
      if [[ "${null_resource.preflight.triggers.ignition_exists}" != "true" ]]; then
        echo "ERROR: Ignition config not found: ${var.ignition_path}" >&2
        exit 1
      fi
      if [[ ! -d "${var.artifacts_dir}" ]]; then
        echo "ERROR: Artifacts directory not found: ${var.artifacts_dir}" >&2
        exit 1
      fi
      if [[ "${null_resource.preflight.triggers.cache_manifest}" == "true" ]]; then

        CACHE_VERSION=$(CACHE_MANIFEST_PATH='${var.cache_manifest_path}' python3 -c "import json, os; v=json.load(open(os.environ['CACHE_MANIFEST_PATH'])).get('version', 'unknown'); print(v[1:] if isinstance(v, str) and len(v) > 1 and v[0] == 'v' else v)" 2>/dev/null || echo "unknown")
        MANIFEST_VERSION=$(MANIFEST_PATH='${var.manifest_path}' python3 -c "import json, os; v=json.load(open(os.environ['MANIFEST_PATH'])).get('version', 'unknown'); print(v[1:] if isinstance(v, str) and len(v) > 1 and v[0] == 'v' else v)" 2>/dev/null || echo "unknown")
        if [[ "$CACHE_VERSION" != "$MANIFEST_VERSION" ]] && [[ "$CACHE_VERSION" != "unknown" ]] && [[ "$MANIFEST_VERSION" != "unknown" ]]; then
          echo "WARN: Version mismatch - cache: $CACHE_VERSION, manifest: $MANIFEST_VERSION"
        fi
      fi
      echo "Pre-flight checks passed for ${var.node_name}"
    EOF
  }
}





module "image_upload" {
  source = "./sub/image-upload"

  depends_on = [null_resource.preflight]

  proxmox_node    = var.proxmox_node
  os_datastore_id = var.os_datastore_id
  vm_name         = var.spec.vm_name
  artifact_prefix = var.artifact_prefix
  artifacts_dir   = var.artifacts_dir
  node_name       = var.node_name
}





locals {
  per_node_spec_vars = {
    node_name    = var.node_name
    node_ip      = try(var.spec.ip_address, "")
    node_gateway = try(var.spec.gateway, "")
    node_dns     = try(var.spec.dns, "")
  }
  ignition_vars_merged = merge(
    var.ignition_vars,
    { ssh_public_key = var.ssh_public_key },
    local.per_node_spec_vars
  )
}

module "ignition_config" {
  source = "./sub/ignition-config"

  depends_on = [module.image_upload]

  proxmox_node         = var.proxmox_node
  snippet_datastore_id = var.snippet_datastore_id
  node_name            = var.node_name
  ignition_path        = var.ignition_path
  ignition_vars        = local.ignition_vars_merged
}





module "vm_provision" {
  source = "./sub/vm-provision"

  depends_on = [module.image_upload, module.ignition_config]

  proxmox_node     = var.proxmox_node
  vm_datastore_id  = var.vm_datastore_id
  spec             = var.spec
  flatcar_file_id  = module.image_upload.flatcar_file_id
  oem_disk_file_id = module.image_upload.oem_disk_file_id
  ignition_file_id = module.ignition_config.ignition_file_id
  dns_servers      = var.dns_servers
  fallback_dns     = var.fallback_dns
}





module "firewall" {
  source = "./sub/firewall"

  depends_on = [module.vm_provision]

  proxmox_node   = var.proxmox_node
  vm_id          = var.spec.vm_id
  firewall_rules = var.spec.firewall_rules
}
