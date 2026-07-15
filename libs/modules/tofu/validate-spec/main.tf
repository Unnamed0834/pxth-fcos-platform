












terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "= 3.3.2"
    }
  }
}

locals {

  defaults = {
    cpu_sockets    = 1
    gpu_mappings   = []
    vm_description = "Infrastructure node"
    hostname       = ""
  }


  required_fields = [
    "vm_name", "vm_id", "ip_address", "gateway", "dns", "hostname",
    "cpu_cores", "memory_mb", "os_disk_size",
    "vlan_id", "network_bridge", "tags", "firewall_rules"
  ]


  valid_fields = [
    "vm_name", "vm_id", "vm_description", "ip_address", "gateway", "dns", "hostname",
    "cpu_cores", "cpu_sockets", "memory_mb", "os_disk_size",
    "vlan_id", "network_bridge", "tags", "firewall_rules",
    "gpu_mappings", "ignition_config",
    "inference_engine", "workload_preset", "nvidia_driver_version",
    "nodes", "name", "name_us"
  ]


  is_multi_node = contains(keys(var.spec), "nodes") && length(try(var.spec.nodes, [])) > 0


  single_node_validation_errors = !local.is_multi_node ? [
    for field in local.required_fields :
    "missing required spec field: ${field}"
    if !contains(keys(try(var.spec, {})), field)
  ] : []

  single_node_unknown_fields = !local.is_multi_node ? [
    for field in keys(var.spec) :
    "unknown spec field: ${field}"
    if !contains(local.valid_fields, field)
  ] : []

  single_node_normalized = !local.is_multi_node ? merge(
    var.spec,
    {
      for k, v in local.defaults : k => v
      if !contains(keys(var.spec), k)
    }
  ) : merge(var.spec, local.defaults)


  multi_node_shared = {
    for k, v in var.spec : k => v
    if k != "nodes"
  }

  multi_node_per_node_required = ["name", "name_us", "vm_id", "ip_address"]

  multi_node_validation_errors = local.is_multi_node ? flatten([
    for node in var.spec.nodes : [
      for field in local.multi_node_per_node_required :
      "node ${node.name}: missing field ${field}"
      if !contains(keys(node), field)
    ]
  ]) : []

  multi_node_unknown_fields = []

  multi_node_specs = local.is_multi_node ? {
    for node in var.spec.nodes : node.name_us => merge(
      node,
      {
        vm_name        = node.name
        hostname       = node.name
        vm_description = "${node.name} — ${try(var.spec.vm_description, "Infrastructure node")}"
        gateway        = try(var.spec.gateway, "")
        dns            = try(var.spec.dns, "")
        cpu_cores      = try(var.spec.cpu_cores, 0)
        cpu_sockets    = try(var.spec.cpu_sockets, 1)
        memory_mb      = try(var.spec.memory_mb, 0)
        os_disk_size   = try(var.spec.os_disk_size, 0)
        vlan_id        = try(var.spec.vlan_id, 0)
        network_bridge = try(var.spec.network_bridge, "")
        tags           = try(var.spec.tags, [])
        firewall_rules = try(var.spec.firewall_rules, [])
      },
      {
        for k, v in local.defaults : k => v
        if !contains(keys(node), k)
      }
    )
  } : {}


  output_spec = local.is_multi_node ? local.multi_node_specs : {
    (var.spec.vm_name) = local.single_node_normalized
  }


  validation_errors = concat(local.single_node_validation_errors, local.multi_node_validation_errors)
  unknown_fields    = concat(local.single_node_unknown_fields, local.multi_node_unknown_fields)
}

resource "null_resource" "validation" {
  triggers = {
    validation_errors = join(", ", local.validation_errors)
    unknown_fields    = join(", ", local.unknown_fields)
  }

  lifecycle {
    precondition {
      condition     = length(local.validation_errors) == 0
      error_message = "Spec validation failed: ${join(", ", local.validation_errors)}"
    }
    precondition {
      condition     = length(local.unknown_fields) == 0
      error_message = "Spec validation failed: ${join(", ", local.unknown_fields)}"
    }
  }
}
