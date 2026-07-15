










terraform {
  required_version = ">= 1.6.0"



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
    sops = {
      source  = "carlpett/sops"
      version = "= 1.4.1"
    }
  }
}







provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token

  ssh {
    agent       = false
    private_key = var.ssh_private_key_content
    username    = "root"
  }
}





module "node" {
  source = "../node"

  providers = {
    proxmox = proxmox
    ct      = ct
    null    = null
  }

  node_name               = var.node_name
  apps_dir                = var.apps_dir
  artifacts_root          = var.artifacts_root
  secrets_dir             = var.secrets_dir
  vars_dir                = var.vars_dir
  manifest_path           = var.manifest_path
  spec_path               = var.spec_path
  proxmox_node            = var.proxmox_node
  datastore_os            = var.datastore_os
  datastore_vm            = var.datastore_vm
  datastore_snippet       = var.datastore_snippet
  interface               = var.interface
  ssh_public_key          = var.ssh_public_key
  cache_manifest_version  = var.cache_manifest_version
  ignition_config_pattern = var.ignition_config_pattern
  resolved_secrets        = var.resolved_secrets
  resolved_variables      = var.resolved_variables
}

output "node_ip" {
  description = "Node IP address(es)"
  value       = module.node.node_ip
}

output "vm_id" {
  description = "VM ID(s)"
  value       = module.node.vm_id
}

output "vm_name" {
  description = "VM name(s)"
  value       = module.node.vm_name
}
