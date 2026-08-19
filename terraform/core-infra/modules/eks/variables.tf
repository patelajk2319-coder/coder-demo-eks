variable "name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the cluster control plane (public + private — public needed for public API endpoint routing)"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnet IDs for the managed node group"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for the system node group"
  type        = string
}

variable "node_desired_count" {
  description = "Desired node count"
  type        = number
}

variable "node_min_count" {
  description = "Minimum node count for autoscaler"
  type        = number
}

variable "node_max_count" {
  description = "Maximum node count for autoscaler"
  type        = number
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
