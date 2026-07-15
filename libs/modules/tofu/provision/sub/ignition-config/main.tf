







terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.123.1"
    }
    ct = {
      source  = "poseidon/ct"
      version = "= 0.14.0"
    }
  }
}

data "ct_config" "ignition" {
  content = templatefile(var.ignition_path, var.ignition_vars)


  strict       = true
  pretty_print = true
}

resource "proxmox_virtual_environment_file" "ignition" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node
  overwrite    = true

  source_raw {
    data      = data.ct_config.ignition.rendered
    file_name = "${var.node_name}-ignition.json"
  }
}

output "ignition_file_id" {
  description = "Proxmox file ID for ignition snippet"
  value       = proxmox_virtual_environment_file.ignition.id
}
