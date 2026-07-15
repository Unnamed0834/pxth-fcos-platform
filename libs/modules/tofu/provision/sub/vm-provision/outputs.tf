

output "vm_id" {
  description = "VM ID"
  value       = proxmox_virtual_environment_vm.this.id
}

output "vm_name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.this.name
}
