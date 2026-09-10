variable "ssh_public_key" {
  description = "Public SSH key material supplied by GitHub Actions."
  type        = string

  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0
    error_message = "ssh_public_key must contain a non-empty public SSH key."
  }
}

variable "aws_region" {
  description = "Region every resource is created in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the app tiers and the database."
  type        = string
  default     = "t3.micro"
}

variable "image_tag" {
  description = <<-EOT
    Container image tag the app tiers boot with. The pipeline sets this to the
    commit SHA so a deployment is a launch template change, which in turn rolls
    the auto scaling groups onto the new images.
  EOT
  type        = string
  default     = "latest"
}

variable "app_instance_count" {
  description = "Instances per load-balanced tier. Two or more removes the single point of failure."
  type        = number
  default     = 2
}

variable "db_user" {
  description = "Database username the backend connects with."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password the backend connects with."
  type        = string
  sensitive   = true
}
