terraform {
  required_version = ">= 1.5.7" # terraform-aws-modules/eks//v21 requires >= 1.5.7

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # terraform-aws-modules/vpc//v6 and /eks//v21 require aws >= 6.28/6.59
    }
  }
  # tls/time/null/cloudinit come in implicitly via terraform-aws-modules/eks.
}

# Auth comes from the standard AWS credential chain, set via .env.
provider "aws" {
  region = local.aws_region
}
