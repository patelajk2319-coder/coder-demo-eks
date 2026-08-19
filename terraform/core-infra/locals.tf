locals {
  name_prefix = "coder-demo"

  common_tags = merge(var.tags, {
    region = var.region
  })
}
