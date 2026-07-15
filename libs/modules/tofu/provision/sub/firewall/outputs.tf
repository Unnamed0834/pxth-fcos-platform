

output "firewall_rules_resource" {
  description = "The firewall rules resource for dependency tracking"
  value       = proxmox_virtual_environment_firewall_rules.this
}
