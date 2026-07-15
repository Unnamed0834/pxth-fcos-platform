

output "node_ip" {
  description = "Node IP Address"
  value       = split("/", var.spec.ip_address)[0]
}

output "vm_id" {
  description = "VM ID"
  value       = var.spec.vm_id
}

output "vm_name" {
  description = "VM Name"
  value       = module.vm_provision.vm_name
}

output "firewall_rules_resource" {
  description = "The firewall rules resource for dependency tracking"
  value       = module.firewall.firewall_rules_resource
}
