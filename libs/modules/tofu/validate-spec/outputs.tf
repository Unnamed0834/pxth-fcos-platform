

output "specs" {
  description = "Normalized node specs keyed by vm_name (single) or name_us (multi)"
  value       = local.output_spec
}

output "is_multi_node" {
  description = "Whether this spec represents a multi-node deployment"
  value       = local.is_multi_node
}
