

variable "resolved_secrets" {
  description = "Pre-resolved secrets map (auto-discovered from shared/ and node/ directories). Supplied via a 0600 sensitive var file."
  type        = map(string)
  sensitive   = true
}

variable "resolved_variables" {
  description = "Pre-resolved variables map (auto-discovered from shared/ and node/ directories)"
  type        = map(string)
}
