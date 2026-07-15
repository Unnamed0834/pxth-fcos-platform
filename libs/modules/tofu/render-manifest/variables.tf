

variable "manifest_path" {
  description = "Path to the node manifest.json file"
  type        = string
}

variable "node_name" {
  description = "Node name for single-node ignition var computation"
  type        = string
}

variable "multi_node" {
  description = "Whether this deployment uses multi-node (passed from validate-spec)"
  type        = bool
  default     = false
}

variable "ignition_config" {
  description = "Ignition config path (passed from validate-spec)"
  type        = string
  default     = ""
}

variable "artifacts_dir" {
  description = "Resolved artifacts directory path for this node"
  type        = string
  default     = ""
}

variable "ignition_extra_vars" {
  description = "Extra ignition variables provided by caller (node networking, secrets, OEM, infra-specific, etc.)"
  type        = map(string)
  default     = {}
}
