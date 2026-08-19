variable "name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private EKS node subnets (one per AZ)"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for the isolated RDS subnets (one per AZ, no internet route)"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name the EKS cluster will use — needed up front to tag subnets for auto-discovery by the cluster autoscaler and AWS Load Balancer Controller"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
