locals {
  name_prefix = "coder-demo"
  # Fixed, not a variable — single-region demo stack; a real region change
  # would also mean revisiting AZ/subnet assumptions anyway.
  aws_region = "eu-west-1"

  # Fixed, not a variable — nothing in this repo ever overrides it.
  postgres_admin_username = "pgadmin"

  common_tags = merge(var.tags, {
    region = local.aws_region
  })
}
