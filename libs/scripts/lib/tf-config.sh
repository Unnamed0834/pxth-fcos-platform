











set -euo pipefail



source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../ci/lib" && pwd)/logging.sh" smoke

if [[ -z "${TF_WORK_DIR:-}" ]]; then
    log_error "TF_WORK_DIR not set"
    exit 1
fi


cat > "$TF_WORK_DIR/main.tf" << MAIN_EOF
terraform {
  required_providers {
    ct = {
      source = "poseidon/ct"
    }
    null = {
      source = "hashicorp/null"
    }
    sops = {
      source = "carlpett/sops"
    }
  }

  backend "s3" {
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

module "entrypoint" {
  source            = "./tofu/entrypoint"
  providers = {
    ct      = ct
    null    = null
    sops    = sops
  }
  node_name             = "${NODE}"
  apps_dir              = "${APPS_DIR}"
  secrets_dir           = "${SECRETS_DIR}"
  vars_dir              = "${COMMON_VARS_DIR}"
  manifest_path         = "${MANIFEST_PATH}"
  spec_path             = "${SPEC_PATH}"
  resolved_secrets      = var.resolved_secrets
  resolved_variables    = var.resolved_variables
  s3_state_access_key   = var.s3_state_access_key
  s3_state_secret_key   = var.s3_state_secret_key
  s3_state_region       = var.s3_state_region
  s3_state_endpoint     = var.s3_state_endpoint
  s3_state_bucket       = var.s3_state_bucket
  proxmox_api_url       = var.proxmox_api_url
  proxmox_api_token     = var.proxmox_api_token
  proxmox_node          = var.proxmox_node
  proxmox_node_ip       = var.proxmox_node_ip
  ssh_private_key_content = var.ssh_private_key_content
  ssh_public_key        = var.ssh_public_key
  datastore_os          = var.datastore_os
  datastore_vm          = var.datastore_vm
  datastore_snippet     = var.datastore_snippet
  interface             = var.interface
  cache_manifest_version = var.cache_manifest_version
  ignition_config_pattern = var.ignition_config_pattern
  os_datastore_id       = var.datastore_os
  vm_datastore_id       = var.datastore_vm
  snippet_datastore_id  = var.datastore_snippet
    }

output "node_ip" {
  description = "Node IP address(es)"
  value       = module.entrypoint.node_ip
}

output "vm_id" {
  description = "VM ID(s)"
  value       = module.entrypoint.vm_id
}
MAIN_EOF


cat > "$TF_WORK_DIR/variables.tf" << 'VARS_EOF'
variable "apps_dir" {
  description = "Path to apps directory containing manifest.json and node-spec.json"
  type        = string
}

variable "s3_state_endpoint" {
  description = "S3 endpoint for Terraform state backend"
  type        = string
  default     = ""
}

variable "s3_state_bucket" {
  description = "S3 bucket for Terraform state backend"
  type        = string
  default     = ""
}

variable "s3_state_region" {
  description = "S3 region for Terraform state backend"
  type        = string
  default     = ""
}

variable "s3_state_access_key" {
  description = "S3 access key for Terraform state backend"
  type        = string
  default     = ""
}

variable "s3_state_secret_key" {
  description = "S3 secret key for Terraform state backend"
  sensitive   = true
  default     = ""
}

variable "resolved_secrets" {
  description = "Pre-resolved secrets map (auto-discovered from shared/ and node/ directories)"
  type        = map(string)
}

variable "resolved_variables" {
  description = "Pre-resolved variables map (auto-discovered from shared/ and node/ directories)"
  type        = map(string)
}

variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "proxmox_node_ip" {
  description = "Proxmox node IP"
  type        = string
}

variable "ssh_private_key_content" {
  description = "SSH private key content"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

variable "datastore_os" {
  description = "OS datastore"
  type        = string
}

variable "datastore_vm" {
  description = "VM datastore"
  type        = string
}

variable "datastore_snippet" {
  description = "Snippet datastore"
  type        = string
}

variable "interface" {
  description = "Network interface"
  type        = string
}

variable "cache_manifest_version" {
  description = "Cache manifest version"
  type        = string
}

variable "ignition_config_pattern" {
  description = "Ignition config pattern"
  type        = string
}

VARS_EOF
