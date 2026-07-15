


variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "snippet_datastore_id" {
  description = "Datastore for ignition snippets"
  type        = string
}

variable "node_name" {
  description = "VM name for ignition file naming"
  type        = string
}

variable "ignition_path" {
  description = "Path to Butane/Ignition template file"
  type        = string
}

variable "ignition_vars" {
  description = "Variables to pass to Ignition template (merged)"
  type        = map(string)
  default     = {}
}
