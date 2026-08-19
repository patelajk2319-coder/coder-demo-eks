variable "cluster_name" {
  description = "Name the EKS cluster will use — determines the CloudWatch log group name EKS control-plane logging writes to"
  type        = string
}

variable "retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
