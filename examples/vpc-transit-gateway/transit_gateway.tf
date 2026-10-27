# These data sources read with the credentials Terraform is using, so they only
# resolve when this account owns the transit gateway. A route table owned by
# another account is not returned by DescribeTransitGatewayRouteTables, even
# after the RAM share is accepted, so with `use_static_tgw_ids` the inputs are
# used as given and the reads are skipped. `tgw_region` covers a TGW in another
# region. An ARN is accepted for upstream resources this account cannot read and
# is reduced to the ID the resources take.
locals {
  tgw_id_input             = can(regex("^arn:", var.transit_gateway_id)) ? basename(var.transit_gateway_id) : var.transit_gateway_id
  tgw_route_table_id_input = can(regex("^arn:", var.transit_gateway_route_table_id)) ? basename(var.transit_gateway_route_table_id) : var.transit_gateway_route_table_id

  tgw_id             = var.use_static_tgw_ids ? local.tgw_id_input : data.aws_ec2_transit_gateway.this[0].id
  tgw_route_table_id = var.use_static_tgw_ids ? local.tgw_route_table_id_input : data.aws_ec2_transit_gateway_route_table.this[0].id
}

data "aws_ec2_transit_gateway" "this" {
  count = var.use_static_tgw_ids ? 0 : 1

  region = var.tgw_region
  id     = local.tgw_id_input
}

data "aws_ec2_transit_gateway_route_table" "this" {
  count = var.use_static_tgw_ids ? 0 : 1

  region = var.tgw_region
  id     = local.tgw_route_table_id_input
}

# The VPC needs at least two subnets in different AZs for a healthy attachment.
# Attachments cannot cross regions, so the VPC and the transit gateway must be in the
# same region; `tgw_region` only affects the data source reads.
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = local.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.intra_subnets

  dns_support = "enable"

  tags = merge(local.common_tags, { Name = var.vpc_name })
}

# Association and propagation are the only resources here that cannot be tagged:
# aws_ec2_transit_gateway_route_table_association/propagation have no `tags`
# argument, so the tags on the attachment are what show up in AWS.
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = var.enable_tgw_association ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = local.tgw_route_table_id

  # A new attachment is auto-associated with the TGW's default route table, so
  # this association fails with Resource.AlreadyAssociated unless the existing
  # association is replaced first. The attachment arguments cannot be used for a
  # shared TGW, so this flag is the only way out on the spoke side.
  replace_existing_association = var.replace_existing_association
}

# Propagation is what makes return traffic work: the TGW route table learns the
# VPC CIDR from this attachment. It only succeeds if the TGW route table allows
# propagation from this attachment, which is usually the TGW owner's decision.
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = var.enable_tgw_propagation ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = local.tgw_route_table_id
}

# Outbound path inside the VPC. Without this the intra route table only has the
# local route, so nothing outside the VPC is reachable.
resource "aws_route" "intra_default_to_tgw" {
  count = var.default_route_to_tgw ? 1 : 0

  route_table_id         = module.vpc.intra_route_table_ids[0]
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.tgw_id

  timeouts {
    create = "5m"
  }
}

# IPv6 path out of the VPC. There is no egress-only internet gateway in this
# topology, so ::/0 goes to the transit gateway. The TGW route table needs a
# matching IPv6 route back to the VPC's /56 for return traffic.
resource "aws_route" "intra_default_ipv6_to_tgw" {
  count = var.enable_ipv6 && var.default_route_to_tgw ? 1 : 0

  route_table_id              = module.vpc.intra_route_table_ids[0]
  destination_ipv6_cidr_block = "::/0"
  transit_gateway_id          = local.tgw_id

  timeouts {
    create = "5m"
  }
}
