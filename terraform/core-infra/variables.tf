variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (NAT gateway / IGW egress only — no workloads scheduled here)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private EKS node subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for the isolated RDS subnets (no route to the internet)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group"
  type        = string
  default     = "m6i.xlarge"
}

variable "node_desired_count" {
  description = "Desired node count for the system node group"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum node count for the system node group autoscaler"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum node count for the system node group autoscaler"
  type        = number
  default     = 3
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
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
