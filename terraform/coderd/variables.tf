variable "coder_url" {
  description = "URL Terraform can reach the Coder API at (a localhost port-forward — CODER_ACCESS_URL is internal-only)"
  type        = string
}

variable "coder_api_token" {
  description = "Long-lived Coder API token for the coderd provider, minted by task init (coder tokens create)"
  type        = string
  sensitive   = true
}

variable "licence_path" {
  description = "Path to an optional Coder Premium license file"
  type        = string
  default     = "../../licence.lic"
}
