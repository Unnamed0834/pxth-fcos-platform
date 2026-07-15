


variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_datastore_id" {
  description = "Datastore for VM disks"
  type        = string
}

variable "spec" {
  description = "Node specification (vm_id, resources, network, etc.)"
  type = object({
    vm_id          = number
    vm_name        = string
    vm_description = string
    cpu_cores      = number
    cpu_sockets    = number
    memory_mb      = number
    os_disk_size   = number
    vlan_id        = number
    network_bridge = string
    ip_address     = string
    gateway        = string
    dns            = string
    tags           = list(string)
    gpu_mappings   = optional(list(string), [])
  })
}

variable "flatcar_file_id" {
  description = "Proxmox file ID for Flatcar disk image"
  type        = string
}

variable "oem_disk_file_id" {
  description = "Proxmox file ID for OEM disk image"
  type        = string
}

variable "ignition_file_id" {
  description = "Ignition config file ID for cloud-init"
  type        = string
}

variable "dns_servers" {
  description = "Explicit DNS servers for VM initialization; when empty, spec.dns and fallback_dns are used."
  type        = list(string)
  default     = []
}

variable "fallback_dns" {
  description = "Optional fallback DNS server (no hardcoded public default)."
  type        = string
  default     = ""
}


