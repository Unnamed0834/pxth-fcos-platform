

output "is_multi_node" {
  description = "Whether this deployment uses multi-node (from validate-spec)"
  value       = local.is_multi_node
}

output "container_images" {
  description = "Container images from artifacts (canonicalized)"
  value       = local.container_images
}

output "ignition_path" {
  description = "Path to Butane/Ignition config file"
  value       = local.ignition_path
}

output "ignition_vars" {
  description = "Ignition variables for single-node or default config"
  value       = local.ignition_vars
  sensitive   = true
}

output "artifacts_dir" {
  description = "Resolved artifacts directory path"
  value       = var.artifacts_dir
}

output "manifest" {
  description = "Raw manifest data"
  value       = local.manifest
  sensitive   = true
}
