terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "~> 0.0"
    }
  }
}

# CODER_ACCESS_URL is the internal NLB hostname — unreachable from the deploy
# machine. var.coder_url is a localhost port-forward address instead (see
# scripts/40_deploy_coderd.sh), same constraint every other script here works
# around.
provider "coderd" {
  url   = var.coder_url
  token = var.coder_api_token
}
