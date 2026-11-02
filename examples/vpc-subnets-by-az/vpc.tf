module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.vpc_name
  cidr = var.vpc_cidr

  # azs comes from the subnet entries (see subnets.tf), which is what keeps every subnet
  # in the AZ it asks for. A tier that is shorter than azs can only cover the leading
  # positions, so it can stop early but cannot skip an AZ.
  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Explicit names beat the module's `<vpc>-<suffix>-<az>` Name tags.
  private_subnet_names = local.private_subnet_names
  public_subnet_names  = local.public_subnet_names

  # An internet gateway and a NAT gateway both need a public subnet to sit in, so a
  # private-only VPC gets neither and relies on the endpoints in endpoints.tf.
  create_igw             = var.create_igw && length(local.public_subnets) > 0
  enable_nat_gateway     = var.enable_nat_gateway && length(local.public_subnets) > 0
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  # With single_nat_gateway = false the private tier gets one route table per subnet,
  # which is what allows a gateway endpoint policy to apply per subnet.
  create_multiple_public_route_tables = var.create_multiple_public_route_tables

  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = local.common_tags

  private_subnet_tags = { Tier = "private" }
  public_subnet_tags  = { Tier = "public" }
}
