locals {
  azs           = formatlist("%s%s", var.aws_region, ["a", "b", "c"])
  intra_subnets = [for i in range(1, 4) : cidrsubnet(var.vpc_cidr, 8, i)]

  # Offsets within the VPC's IPv6 /56. Kept empty when IPv6 is off so the module
  # leaves the subnet IPv6 settings untouched.
  ipv6_prefixes = var.enable_ipv6 ? var.intra_subnet_ipv6_prefixes : []

  common_tags = {
    Environment = var.environment
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.vpc_name
  cidr = var.vpc_cidr

  # IPv4 from `vpc_cidr`; IPv6 from `ipv6_cidr` when provided, otherwise AWS
  # assigns a /56 from the Amazon pool when enable_ipv6 is true.
  enable_ipv6 = var.enable_ipv6
  ipv6_cidr   = var.ipv6_cidr

  # Intra subnets: no internet routing of their own. Everything leaves through
  # the transit gateway attachment (see transit_gateway.tf).
  azs           = local.azs
  intra_subnets = local.intra_subnets

  intra_subnet_ipv6_prefixes                   = local.ipv6_prefixes
  intra_subnet_assign_ipv6_address_on_creation = var.enable_ipv6 && var.assign_ipv6_address_on_creation

  # No public components at all. The egress-only IGW would have nothing to route,
  # so IPv6 leaves through the transit gateway instead (see transit_gateway.tf).
  create_igw             = false
  enable_nat_gateway     = false
  create_egress_only_igw = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags

  intra_subnet_tags = { Tier = "intra" }
}
