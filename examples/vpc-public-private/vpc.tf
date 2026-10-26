locals {
  azs             = formatlist("%s%s", var.aws_region, ["a", "b", "c"])
  private_subnets = [for i in range(1, 4) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i in range(101, 104) : cidrsubnet(var.vpc_cidr, 8, i)]

  # Offsets within the VPC's IPv6 /56. Kept empty when IPv6 is off so the module
  # leaves the subnet IPv6 settings untouched. Prefixes must be unique across the
  # whole /56, so the private and public ranges do not overlap.
  private_ipv6_prefixes = var.enable_ipv6 ? var.private_subnet_ipv6_prefixes : []
  public_ipv6_prefixes  = var.enable_ipv6 ? var.public_subnet_ipv6_prefixes : []

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

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  private_subnet_ipv6_prefixes                   = local.private_ipv6_prefixes
  public_subnet_ipv6_prefixes                    = local.public_ipv6_prefixes
  private_subnet_assign_ipv6_address_on_creation = var.enable_ipv6 && var.assign_ipv6_address_on_creation
  public_subnet_assign_ipv6_address_on_creation  = var.enable_ipv6 && var.assign_ipv6_address_on_creation

  enable_nat_gateway = true
  # One NAT gateway for the example. Use one per AZ (single_nat_gateway = false) in production.
  single_nat_gateway = true

  # Egress-only IGW plus the ::/0 route on the public route table when IPv6 is on.
  create_egress_only_igw = var.enable_ipv6

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags

  private_subnet_tags = { Tier = "private" }
  public_subnet_tags  = { Tier = "public" }
}
