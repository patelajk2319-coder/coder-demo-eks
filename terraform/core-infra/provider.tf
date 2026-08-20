terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Auth is sourced from the standard AWS credential chain (~/.aws/config,
# ~/.aws/credentials, or AWS_PROFILE) — set via .env and exported by the deploy script.
provider "aws" {
  region = var.region
}
