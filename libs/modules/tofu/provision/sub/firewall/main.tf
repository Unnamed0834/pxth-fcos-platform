










terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.123.1"
    }
  }
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      type    = rule.value.type
      action  = rule.value.action
      proto   = lookup(rule.value, "proto", "tcp")
      dport   = lookup(rule.value, "dport", null)
      comment = lookup(rule.value, "comment", "")
    }
  }
}
