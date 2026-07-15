






terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.123.1"
    }
  }
}

locals {
  artifact_prefix = var.artifact_prefix != "" ? var.artifact_prefix : replace(var.vm_name, "-", "_")
  oem_disk_name   = "${replace(var.node_name != "" ? var.node_name : local.artifact_prefix, "-", "_")}_oem_disk.raw"
}

resource "proxmox_virtual_environment_file" "flatcar" {
  content_type = "import"
  datastore_id = var.os_datastore_id
  node_name    = var.proxmox_node
  overwrite    = true

  source_file {
    path = "${var.artifacts_dir}/upload/${local.artifact_prefix}_flatcar_production_proxmoxve_image.qcow2"
  }
}

resource "proxmox_virtual_environment_file" "oem_disk" {
  content_type = "import"
  datastore_id = var.os_datastore_id
  node_name    = var.proxmox_node
  overwrite    = true

  source_file {
    path = "${var.artifacts_dir}/upload/${local.oem_disk_name}"
  }
}

output "flatcar_file_id" {
  description = "Proxmox file ID for Flatcar disk image"
  value       = proxmox_virtual_environment_file.flatcar.id
}

output "oem_disk_file_id" {
  description = "Proxmox file ID for OEM disk image"
  value       = proxmox_virtual_environment_file.oem_disk.id
}
