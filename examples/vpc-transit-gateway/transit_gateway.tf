data "aws_ec2_transit_gateway" "this" {
  id = var.transit_gateway_id
}

data "aws_ec2_transit_gateway_route_table" "this" {
  id = var.transit_gateway_route_table_id
}

# The VPC needs at least two subnets in different AZs for a healthy attachment.
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = data.aws_ec2_transit_gateway.this.id
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
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.this.id
}

# Propagation is what makes return traffic work: the TGW route table learns the
# VPC CIDR from this attachment. It only succeeds if the TGW route table allows
# propagation from this attachment, which is usually the TGW owner's decision.
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = var.enable_tgw_propagation ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this.id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.this.id
}

# Outbound path inside the VPC. Without this the intra route table only has the
# local route, so nothing outside the VPC is reachable.
resource "aws_route" "intra_default_to_tgw" {
  count = var.default_route_to_tgw ? 1 : 0

  route_table_id         = module.vpc.intra_route_table_ids[0]
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = data.aws_ec2_transit_gateway.this.id

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
  transit_gateway_id          = data.aws_ec2_transit_gateway.this.id

  timeouts {
    create = "5m"
  }
}
