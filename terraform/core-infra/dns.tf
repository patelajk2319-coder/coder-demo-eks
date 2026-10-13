# Private zone, associated only with this VPC — gives Coder a stable
# hostname before its NLB exists, so no more guessing CODER_ACCESS_URL
# post-apply. external-dns (terraform/addons) populates records in it.

resource "aws_route53_zone" "internal" {
  name = "${local.name_prefix}.internal"

  vpc {
    vpc_id = module.vpc.vpc_id
  }

  tags = local.common_tags
}
