variable "ssh_public_key" {
  description = "Public SSH key material supplied by GitHub Actions."
  type        = string

  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must contain a non-empty public SSH key."
  }
}
