

variable "spec" {
  description = "Node spec from node-spec.json. Single-node: object with vm fields. Multi-node: object with 'nodes' array and shared fields."
  type        = any
}
