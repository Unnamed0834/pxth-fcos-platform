

output "node_ip" {
  description = "Node IP address(es)"
  value       = { for k, v in module.provision : k => v.node_ip }
}

output "vm_id" {
  description = "VM ID(s)"
  value       = { for k, v in module.provision : k => v.vm_id }
}

output "vm_name" {
  description = "VM name(s)"
  value       = { for k, v in module.provision : k => v.vm_name }
}

output "ignition_path" {
  description = "Path to Butane/Ignition config file(s)"
  value       = { for k, v in module.render_manifest : k => v.ignition_path }
}

output "artifacts_dir" {
  description = "Resolved artifacts directory path"
  value       = { for k, v in module.render_manifest : k => v.artifacts_dir }
}
