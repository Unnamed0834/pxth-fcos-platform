

variable "node_name" {
  description = "VM name"
  type        = string
}

variable "manifest_path" {
  description = "Absolute path to the node manifest.json file (artifacts + OEM)"
  type        = string
}

variable "spec_path" {
  description = "Absolute path to the node spec JSON file (VM specs, VLAN, network, firewall)"
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
  description = "Absolute path to apps directory containing manifest.json and node-spec.json"
  type        = string
}

variable "artifacts_root" {
  description = "Explicit absolute path to the artifacts/ root. When empty, derived from apps_dir."
  type        = string
  default     = ""
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
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

variable "ssh_public_key" {
  description = "SSH public key for provisioning"
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

variable "resolved_secrets" {
  description = "Pre-resolved secrets map (supplied via 0600 sensitive var file)"
  type        = map(string)
  sensitive   = true
}

variable "resolved_variables" {
  description = "Pre-resolved variables map (auto-discovered from shared/ and node/ directories)"
  type        = map(string)
}
