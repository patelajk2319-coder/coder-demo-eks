variable "name" {
  description = "Name of the RDS instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "database_subnet_ids" {
  description = "Isolated subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group ID permitted to reach RDS on 5432 (the EKS cluster security group)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major engine version"
  type        = string
}

variable "instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
}

variable "storage_gb" {
  description = "Allocated storage in GB"
  type        = number
}

variable "admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
}

variable "admin_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
