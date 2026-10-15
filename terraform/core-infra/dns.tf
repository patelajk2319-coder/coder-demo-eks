# Private zone — gives Coder a stable hostname before its NLB exists, so no
# more guessing CODER_ACCESS_URL post-apply. external-dns (terraform/addons)
# populates records in it. A team cluster that needs to resolve it (e.g. to
# reach the control plane) associates its own VPC via a standalone
# aws_route53_zone_association — ignore_changes keeps that from fighting
# this resource's own vpc block for ownership of the association list.
resource "aws_route53_zone" "internal" {
  name = "${local.name_prefix}.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [vpc]
  }
}
