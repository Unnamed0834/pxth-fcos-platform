



variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://pve-01.example.com:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (e.g., root@pam!terraform)"
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Node identifier"
  type        = string
}

variable "secrets_dir" {
  description = "Path to directory containing SOPS-encrypted secrets"
  type        = string
}

variable "vars_dir" {
  description = "Path to directory containing plain YAML variables"
  type        = string
}

variable "apps_dir" {
  description = "Path to apps directory containing manifest.json and node-spec.json"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name (e.g., pve-01)"
  type        = string
}

variable "proxmox_node_ip" {
  description = "Proxmox node IP. Kept for CLI compatibility; not consumed."
  type        = string
  default     = ""
}

variable "artifacts_root" {
  description = "Explicit absolute path to the artifacts/ root; when empty it is derived from apps_dir."
  type        = string
  default     = ""
}

variable "os_datastore_id" {
  description = "Proxmox datastore ID for OS disk and OEM disk uploads"
  type        = string
}

variable "vm_datastore_id" {
  description = "Proxmox datastore ID for VM disks"
  type        = string
}

variable "snippet_datastore_id" {
  description = "Proxmox datastore ID for ignition snippets"
  type        = string
}

variable "manifest_path" {
  description = "Path to the node manifest.json file (artifacts + OEM)"
  type        = string
  default     = ""
}

variable "spec_path" {
  description = "Path to the node spec JSON file (VM specs, VLAN, network, firewall)"
  type        = string
  default     = ""
}

variable "ssh_private_key_content" {
  description = "SSH private key content (decrypted from SOPS)"
  type        = string
  sensitive   = true
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
  sensitive   = true
  default     = ""
}

variable "s3_state_secret_key" {
  description = "S3 secret key for Terraform state backend"
  type        = string
  sensitive   = true
  default     = ""
}

variable "datastore_os" {
  description = "Datastore for OS disk"
  type        = string
}

variable "datastore_vm" {
  description = "Datastore for VM disks"
  type        = string
}

variable "datastore_snippet" {
  description = "Datastore for ignition snippets"
  type        = string
}

variable "interface" {
  description = "Proxmox network interface"
  type        = string
}

variable "cache_manifest_version" {
  description = "Cache manifest version directory"
  type        = string
}

variable "ignition_config_pattern" {
  description = "Pattern for ignition config filename"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for provisioning"
  type        = string
}

variable "resolved_secrets" {
  description = "Pre-resolved secrets map (supplied via 0600 sensitive var file)"
  type        = map(string)
  sensitive   = true
}

variable "resolved_variables" {
  description = "Pre-resolved variables map (auto-discovered from shared/ and node/ directories)"
  type        = map(string)
}
