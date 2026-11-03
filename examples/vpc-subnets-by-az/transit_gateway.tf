# Optional connection to a pre-existing transit gateway, off by default. The data sources
# only resolve when this account owns the transit gateway: DescribeTransitGatewayRouteTables
# does not return a route table owned by another account, even after the RAM share is
# accepted, so with `use_static_tgw_ids` the inputs are used as given and the reads are
# skipped. An ARN is accepted and reduced to the ID the resources take, because
# `aws ec2 get-transit-gateway-default-route-table-id` prints an ARN.
locals {
  tgw_id_input             = var.transit_gateway_id == null ? null : (can(regex("^arn:", var.transit_gateway_id)) ? basename(var.transit_gateway_id) : var.transit_gateway_id)
  tgw_route_table_id_input = var.transit_gateway_route_table_id == null ? null : (can(regex("^arn:", var.transit_gateway_route_table_id)) ? basename(var.transit_gateway_route_table_id) : var.transit_gateway_route_table_id)

  # The route table is only touched by the association and the propagation, so with both off an
  # attachment does not need one: the input can stay null and the read is skipped.
  tgw_route_table_used = var.enable_tgw_association || var.enable_tgw_propagation

  tgw_id             = var.enable_transit_gateway && !var.use_static_tgw_ids ? data.aws_ec2_transit_gateway.this[0].id : local.tgw_id_input
  tgw_route_table_id = var.enable_transit_gateway && local.tgw_route_table_used && !var.use_static_tgw_ids ? data.aws_ec2_transit_gateway_route_table.this[0].id : local.tgw_route_table_id_input

  # The attachment takes subnets from this VPC; the private VLANs are the default because
  # that is where the workloads are. Attachments cannot cross regions, so `tgw_region` only
  # affects the data source reads.
  tgw_subnets = coalesce(var.transit_gateway_subnets, module.vpc.private_subnets)

  # Private route tables are sized by the module's NAT gateway count, which applies even when
  # NAT is off: one table with single_nat_gateway, one per AZ with one_nat_gateway_per_az,
  # otherwise one per subnet position. The default route goes on each of them.
  tgw_route_tables = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(local.azs) : local.max_subnet_count
}

data "aws_ec2_transit_gateway" "this" {
  count = var.enable_transit_gateway && !var.use_static_tgw_ids ? 1 : 0

  region = var.tgw_region
  id     = local.tgw_id_input
}

data "aws_ec2_transit_gateway_route_table" "this" {
  count = var.enable_transit_gateway && local.tgw_route_table_used && !var.use_static_tgw_ids ? 1 : 0

  region = var.tgw_region
  id     = local.tgw_route_table_id_input
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.enable_transit_gateway ? 1 : 0

  transit_gateway_id = local.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = local.tgw_subnets

  dns_support = var.tgw_dns_support ? "enable" : "disable"

  tags = merge(local.common_tags, { Name = var.vpc_name })
}

# Association and propagation are the only resources here that cannot be tagged:
# aws_ec2_transit_gateway_route_table_association/propagation have no `tags` argument, so
# the tags on the attachment are what show up in AWS.
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = var.enable_transit_gateway && var.enable_tgw_association ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = local.tgw_route_table_id

  # A new attachment is auto-associated with the TGW's default route table, so this
  # association fails with Resource.AlreadyAssociated unless the existing association is
  # replaced first. The attachment arguments cannot be used for a shared TGW, so this flag
  # is the only way out on the spoke side.
  replace_existing_association = var.replace_existing_association
}

# Propagation is what makes return traffic work: the TGW route table learns the VPC CIDR
# from this attachment. It only succeeds if the TGW route table allows propagation from this
# attachment, which is usually the TGW owner's decision.
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = var.enable_transit_gateway && var.enable_tgw_propagation ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = local.tgw_route_table_id
}

# One default route per private route table. Without it a private VLAN only has its local
# route, so nothing outside the VPC is reachable from it. Gateway endpoints are unaffected:
# their prefix-list routes are more specific than 0.0.0.0/0 and win over the TGW route.
resource "aws_route" "private_default_to_tgw" {
  count = var.enable_transit_gateway && var.default_route_to_tgw ? local.tgw_route_tables : 0

  route_table_id         = element(module.vpc.private_route_table_ids, count.index)
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.tgw_id

  timeouts {
    create = "5m"
  }
}

check "transit_gateway_config" {
  assert {
    condition     = !var.enable_transit_gateway || (var.transit_gateway_id != null && var.transit_gateway_route_table_id != null)
    error_message = "enable_transit_gateway needs both transit_gateway_id and transit_gateway_route_table_id."
  }

  assert {
    condition     = !var.enable_transit_gateway || var.tgw_region == null || var.tgw_region == var.aws_region
    error_message = "A VPC attachment cannot cross regions, so tgw_region has to equal aws_region; the attachment fails at apply when it does not."
  }

  assert {
    condition = (
      !var.enable_transit_gateway ||
      (var.transit_gateway_subnets == null ? length(var.private_subnets) : length(var.transit_gateway_subnets)) >= 2
    )
    error_message = "The attachment needs at least two subnets of this VPC, in different AZs for resilience. The private tier is the default, so a private tier with one subnet needs transit_gateway_subnets."
  }

  assert {
    condition     = !var.enable_transit_gateway || !var.default_route_to_tgw || !var.enable_nat_gateway
    error_message = "default_route_to_tgw and enable_nat_gateway both put a 0.0.0.0/0 route on the same private route tables. Pick one as the default path out of the VPC."
  }
}
