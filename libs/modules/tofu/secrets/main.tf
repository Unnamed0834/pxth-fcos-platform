
























output "api_token" {
  description = "Proxmox API token"
  value       = var.resolved_secrets["api_token"]
  sensitive   = true
}

output "pve_root_password" {
  description = "Proxmox root password"
  value       = try(var.resolved_secrets["pve_root_password"], "")
  sensitive   = true
}

output "private_key" {
  description = "SSH private key"
  value       = var.resolved_secrets["private_key"]
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key"
  value       = var.resolved_variables["ssh_public_key"]
}

output "proxmox_api_url" {
  description = "Proxmox API URL"
  value       = var.resolved_variables["pve_url"]
}

output "proxmox_node" {
  description = "Proxmox node name"
  value       = var.resolved_variables["node"]
}

output "proxmox_node_ip" {
  description = "Proxmox node IP"
  value       = var.resolved_variables["pve_node_ip"]
}

output "terraform_plugin_cache_path" {
  description = "Terraform plugin cache path"
  value       = try(var.resolved_variables["path"], "")
}

output "s3_state_region" {
  description = "S3 state region"
  value       = var.resolved_variables["region"]
}

output "datastore_os" {
  description = "OS datastore"
  value       = var.resolved_variables["datastore_os"]
}

output "datastore_vm" {
  description = "VM datastore"
  value       = var.resolved_variables["datastore_vm"]
}

output "datastore_snippet" {
  description = "Snippet datastore"
  value       = var.resolved_variables["datastore_snippet"]
}

output "interface" {
  description = "Network interface"
  value       = var.resolved_variables["interface"]
}

output "cache_manifest_version" {
  description = "Cache manifest version"
  value       = var.resolved_variables["cache_manifest_version"]
}

output "ignition_config_pattern" {
  description = "Ignition config pattern"
  value       = var.resolved_variables["ignition_config_pattern"]
}
