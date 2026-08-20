variable "postgres_admin_username" {
  description = "RDS PostgreSQL administrator username"
  type        = string
  default     = "pgadmin"
}

variable "postgres_admin_password" {
  description = "RDS PostgreSQL administrator password"
  type        = string
  sensitive   = true
}

variable "postgres_engine_version" {
  description = "PostgreSQL major engine version"
  type        = string
  default     = "16"
}

variable "postgres_instance_class" {
  description = "Instance class for the RDS PostgreSQL instance"
  type        = string
  default     = "db.t3.medium"
}

variable "postgres_storage_gb" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
  default     = 32
}

variable "anthropic_api_key" {
  description = "Anthropic API key — stored in Secrets Manager, never passed to Coder Terraform"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "coder-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}
