


variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "os_datastore_id" {
  description = "Datastore for OS disk uploads"
  type        = string
}

variable "vm_name" {
  description = "VM name for artifact path resolution"
  type        = string
}

variable "artifact_prefix" {
  description = "Artifact prefix for image upload (from manifest app name, not per-node vm_name)"
  type        = string
  default     = ""
}

variable "artifacts_dir" {
  description = "Path to artifacts directory"
  type        = string
}

variable "node_name" {
  description = "Subnode name for multi-node OEM disk path resolution"
  type        = string
  default     = ""
}
