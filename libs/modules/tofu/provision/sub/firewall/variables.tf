

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID to apply firewall rules to"
  type        = number
}

variable "firewall_rules" {
  description = "List of firewall rules to apply"
  type = list(object({
    type    = string
    action  = string
    proto   = optional(string, "tcp")
    dport   = optional(string, null)
    comment = optional(string, "")
  }))
  default = []
}
