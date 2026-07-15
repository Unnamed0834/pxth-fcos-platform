
























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





module "secrets" {
  source = "../secrets"




  resolved_secrets   = var.resolved_secrets
  resolved_variables = var.resolved_variables
}





locals {
  node_name_from_manifest = basename(dirname(var.manifest_path))




  project_root   = pathexpand(dirname(var.apps_dir))
  artifacts_root = var.artifacts_root != "" ? pathexpand(var.artifacts_root) : "${local.project_root}/artifacts"
  artifacts_dir  = "${local.artifacts_root}/${local.node_name_from_manifest}"

  cache_manifest_path = "${local.artifacts_dir}/versions/${var.cache_manifest_version}/.cache-manifest.json"
  oem_metadata_path   = "${local.artifacts_dir}/upload/oem-metadata.json"


  specs_map = module.validate_spec.specs


  _secrets_parent         = dirname(var.secrets_dir)
  app_dir                 = basename(dirname(var.manifest_path))
  ignition_config_default = format(var.ignition_config_pattern, local.app_dir)
  ignition_config_raw     = (module.validate_spec.is_multi_node ? try(values(local.specs_map)[0].ignition_config, local.ignition_config_default) : try(local.specs_map[var.node_name].ignition_config, local.ignition_config_default))
  ignition_config_path    = (startswith(local.ignition_config_raw, "/") ? local.ignition_config_raw : "${local._secrets_parent}/apps/${local.app_dir}/${local.ignition_config_raw}")



  oem_metadata = jsondecode(file(local.oem_metadata_path))


  oem_metadata_for_each = {
    for key, spec in local.specs_map : key => {
      sha256 = module.validate_spec.is_multi_node ? try(local.oem_metadata[key].oem_disk_sha256, "") : try(local.oem_metadata.oem_disk_sha256, "")
      size   = module.validate_spec.is_multi_node ? try(local.oem_metadata[key].tarball_size, "") : try(local.oem_metadata.tarball_size, "")
    }
  }






  ignition_extra_for_each = {
    for key, spec in local.specs_map : key => merge(
      var.resolved_variables,
      {
        node_hostname   = spec.hostname
        node_ip         = try(spec.ip_address, "")
        node_gateway    = try(local.specs_map[key].gateway, "")
        node_dns        = try(local.specs_map[key].dns, "")
        OEM_DISK_SHA256 = local.oem_metadata_for_each[key].sha256
        TARBALL_SIZE    = local.oem_metadata_for_each[key].size
      }
    )
  }
}





module "validate_spec" {
  source = "../validate-spec"

  spec = jsondecode(file(var.spec_path))
}





module "render_manifest" {
  for_each = local.specs_map

  source = "../render-manifest"

  node_name           = each.key
  manifest_path       = var.manifest_path
  multi_node          = module.validate_spec.is_multi_node
  ignition_config     = local.ignition_config_path
  artifacts_dir       = local.artifacts_dir
  ignition_extra_vars = local.ignition_extra_for_each[each.key]
}





module "provision" {
  for_each = local.specs_map

  source = "../provision"
  providers = {
    proxmox = proxmox
    ct      = ct
    null    = null
  }

  node_name            = each.key
  spec                 = each.value
  ignition_path        = module.render_manifest[each.key].ignition_path
  ignition_vars        = module.render_manifest[each.key].ignition_vars
  ssh_public_key       = var.ssh_public_key
  proxmox_node         = var.proxmox_node
  artifacts_dir        = local.artifacts_dir
  os_datastore_id      = var.datastore_os
  vm_datastore_id      = var.datastore_vm
  snippet_datastore_id = var.datastore_snippet
  cache_manifest_path  = local.cache_manifest_path
  manifest_path        = var.manifest_path
  artifact_prefix      = replace(local.app_dir, "-", "_")
}
