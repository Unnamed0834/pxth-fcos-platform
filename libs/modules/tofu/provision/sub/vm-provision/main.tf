







terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.123.1"
    }
  }
}

locals {


  dns_servers = length(var.dns_servers) > 0 ? var.dns_servers : compact([var.spec.dns, var.fallback_dns])
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.spec.vm_name
  description = var.spec.vm_description
  node_name   = var.proxmox_node
  vm_id       = var.spec.vm_id

  tags = var.spec.tags

  on_boot             = true
  started             = true
  timeout_shutdown_vm = 60
  timeout_stop_vm     = 30
  timeout_create      = 300
  stop_on_destroy     = true

  bios    = "ovmf"
  machine = "q35"

  agent {
    enabled = true
  }

  cpu {
    cores   = var.spec.cpu_cores
    sockets = var.spec.cpu_sockets
    type    = "host"
  }

  memory {
    dedicated = var.spec.memory_mb
  }

  disk {
    datastore_id = var.vm_datastore_id
    file_id      = var.flatcar_file_id
    interface    = "scsi0"
    size         = var.spec.os_disk_size
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  disk {
    datastore_id = var.vm_datastore_id
    file_id      = var.oem_disk_file_id
    interface    = "scsi9"
    size         = 5
    file_format  = "raw"
    ssd          = true
    discard      = "on"
  }

  initialization {
    datastore_id = var.vm_datastore_id

    dns {
      servers = local.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.spec.ip_address
        gateway = var.spec.gateway
      }
    }

    vendor_data_file_id = var.ignition_file_id
  }

  network_device {
    bridge   = var.spec.network_bridge
    firewall = true
    model    = "virtio"
    vlan_id  = var.spec.vlan_id
    queues   = var.spec.cpu_cores
  }

  dynamic "hostpci" {
    for_each = var.spec.gpu_mappings
    content {
      device  = "hostpci${index(var.spec.gpu_mappings, hostpci.value)}"
      mapping = hostpci.value
      rombar  = false
    }
  }

  operating_system {
    type = "l26"
  }

  depends_on = [
    var.flatcar_file_id,
    var.oem_disk_file_id,
    var.ignition_file_id,
  ]
}
