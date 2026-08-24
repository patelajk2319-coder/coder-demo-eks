variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "coder-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}
