


variable "node_name" {
  description = "VM name"
  type        = string
}

variable "spec" {
  description = "Node spec from node-spec.json (vm_id, ip, cpu, memory, disk, vlan, tags, firewall_rules, ...)"
  type        = any
}

variable "ignition_path" {
  description = "Path to Butane/Ignition config file"
  type        = string
}

variable "ignition_vars" {
  description = "Variables to pass to Ignition template"
  type        = map(string)
  default     = {}
}

variable "ssh_public_key" {
  description = "SSH public key for node access"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "artifacts_dir" {
  description = "Absolute path to artifacts directory for this node"
  type        = string
}

variable "os_datastore_id" {
  description = "Datastore for OS disk and OEM disk uploads"
  type        = string
}

variable "vm_datastore_id" {
  description = "Datastore for VM disks"
  type        = string
}

variable "snippet_datastore_id" {
  description = "Datastore for ignition snippets"
  type        = string
}

variable "artifact_prefix" {
  description = "Artifact prefix for image upload (from manifest app name, not per-node vm_name)"
  type        = string
  default     = ""
}

variable "cache_manifest_path" {
  description = "Absolute path to cache manifest JSON (preflight only)"
  type        = string
  default     = ""
}

variable "manifest_path" {
  description = "Absolute path to manifest JSON (preflight only)"
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "Explicit DNS servers for VM initialization. When empty, spec.dns (+ optional fallback_dns) is used."
  type        = list(string)
  default     = []
}

variable "fallback_dns" {
  description = "Optional fallback DNS appended when dns_servers is empty. No public-DNS default is assumed."
  type        = string
  default     = ""
}
