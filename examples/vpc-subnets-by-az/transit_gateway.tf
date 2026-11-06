# Optional connection to a pre-existing transit gateway, off by default. The data sources
# only resolve when this account owns the transit gateway: DescribeTransitGatewayRouteTables
# does not return a route table owned by another account, even after the RAM share is
# accepted, so with `use_static_tgw_ids` the inputs are used as given and the reads are
# skipped. An ARN is accepted and reduced to the ID the resources take, because
# `aws ec2 get-transit-gateway-default-route-table-id` prints an ARN.
locals {
  tgw_id_input = var.transit_gateway_id == null ? null : (can(regex("^arn:", var.transit_gateway_id)) ? basename(var.transit_gateway_id) : var.transit_gateway_id)

  # Route tables are entries, one per table, so two tables is simply two entries. Each entry is
  # keyed by the ID or ARN as it was given - that key is what the outputs use - and the flags an
  # entry does not set fall back to the module-wide defaults.
  tgw_entries = [
    for e in var.transit_gateway_route_tables : merge(e, {
      key       = e.id,
      id        = can(regex("^arn:", e.id)) ? basename(e.id) : e.id,
      associate = coalesce(e.associate, var.enable_tgw_association),
      propagate = coalesce(e.propagate, var.enable_tgw_propagation),
    })
  ]

  # A table that is not propagated has nothing learning this VPC's CIDR, so the default for it is
  # the static route for vpc_cidr; a propagated table already has that route, so it gets none
  # unless the entry names cidrs.
  tgw_route_tables = {
    for e in local.tgw_entries : e.key => merge(e, {
      cidrs = length(coalesce(e.cidrs, [])) > 0 ? coalesce(e.cidrs, []) : (e.propagate ? [] : [var.vpc_cidr])
    })
  }

  # A table that is neither associated, propagated, nor written to is not touched at all, so its
  # read is skipped for the same reason as before.
  tgw_tables_read = { for k, t in local.tgw_route_tables : k => t if !var.use_static_tgw_ids && (t.associate || t.propagate || length(t.cidrs) > 0) }

  # Static routes flattened to one resource per table and destination, keyed by both so two tables
  # can hold the same CIDR.
  tgw_static_routes = {
    for pair in flatten([for k, t in local.tgw_route_tables : [for cidr in t.cidrs : { table = k, cidr = cidr }]]) :
    "${pair.table}|${pair.cidr}" => pair
  }

  tgw_id              = var.enable_transit_gateway && !var.use_static_tgw_ids ? data.aws_ec2_transit_gateway.this[0].id : local.tgw_id_input
  tgw_route_table_ids = { for k, t in local.tgw_route_tables : k => contains(keys(local.tgw_tables_read), k) ? data.aws_ec2_transit_gateway_route_table.this[k].id : t.id }

  # The attachment takes subnets from this VPC; the private VLANs are the default because
  # that is where the workloads are. Attachments cannot cross regions, so `tgw_region` only
  # affects the data source reads.
  tgw_subnets = coalesce(var.transit_gateway_subnets, module.vpc.private_subnets)

  # Private route tables are sized by the module's NAT gateway count, which applies even when
  # NAT is off: one table with single_nat_gateway, one per AZ with one_nat_gateway_per_az,
  # otherwise one per subnet position. The default route goes on each of them.
  #
  # This has to be the module's formula rather than length(module.vpc.private_route_table_ids):
  # those IDs are created resources, so they are unknown at plan time and neither a count nor a
  # for_each built from them can be planned. The formula is the same one the module uses
  # (nat_gateway_count), so the counts agree by construction.
  private_route_table_count = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(local.azs) : local.max_subnet_count
}

data "aws_ec2_transit_gateway" "this" {
  count = var.enable_transit_gateway && !var.use_static_tgw_ids ? 1 : 0

  region = var.tgw_region
  id     = local.tgw_id_input
}

data "aws_ec2_transit_gateway_route_table" "this" {
  for_each = local.tgw_tables_read

  region = var.tgw_region
  id     = each.value.id
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
#
# Every key here comes from the entries, which are variables, so the for_each can be planned;
# one association per table the entry associates with.
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.enable_transit_gateway ? { for k, t in local.tgw_route_tables : k => t if t.associate } : {}

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = local.tgw_route_table_ids[each.key]

  # A new attachment is auto-associated with the TGW's default route table, so this
  # association fails with Resource.AlreadyAssociated unless the existing association is
  # replaced first. The attachment arguments cannot be used for a shared TGW, so this flag
  # is the only way out on the spoke side. Only the entry for that table can replace
  # anything; the other tables have no prior association, so the flag does nothing there.
  replace_existing_association = var.replace_existing_association
}

# Propagation is what makes return traffic work: the TGW route table learns the VPC CIDR
# from this attachment. It only succeeds if the TGW route table allows propagation from this
# attachment, which is usually the TGW owner's decision.
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.enable_transit_gateway ? { for k, t in local.tgw_route_tables : k => t if t.propagate } : {}

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = local.tgw_route_table_ids[each.key]
}

# The static route is the other way a table learns a destination: it is written by hand instead
# of learned from the attachment, which is what you need on a table that does not accept
# propagation. It only forwards once the attachment is associated with that same table.
# aws_ec2_transit_gateway_route has no `tags` argument and no timeouts block, so nothing here
# is tagged, and on a table owned by another account the write is the hub owner's call:
# without the share granting it the route fails at apply with AccessDenied.
resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.enable_transit_gateway ? local.tgw_static_routes : {}

  transit_gateway_route_table_id = local.tgw_route_table_ids[each.value.table]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  destination_cidr_block         = each.value.cidr
}

# One default route per private route table, which is what covers every private subnet: the
# module associates each subnet with one of these tables, so a subnet that is the second entry in
# its AZ still gets the route. Without it a private VLAN only has its local route, so nothing
# outside the VPC is reachable from it. Gateway endpoints are unaffected: their prefix-list routes
# are more specific than 0.0.0.0/0 and win over the TGW route.
resource "aws_route" "private_default_to_tgw" {
  count = var.enable_transit_gateway && var.default_route_to_tgw ? local.private_route_table_count : 0

  route_table_id         = element(module.vpc.private_route_table_ids, count.index)
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.tgw_id

  timeouts {
    create = "5m"
  }
}

check "transit_gateway_config" {
  assert {
    condition     = !var.enable_transit_gateway || (var.transit_gateway_id != null && length(var.transit_gateway_route_tables) > 0)
    error_message = "enable_transit_gateway needs transit_gateway_id and at least one entry in transit_gateway_route_tables; two tables is two entries."
  }

  assert {
    condition     = length(distinct([for e in var.transit_gateway_route_tables : e.id])) == length(var.transit_gateway_route_tables)
    error_message = "Every route table entry is keyed by the ID it was given, so the same table cannot appear twice in transit_gateway_route_tables."
  }

  assert {
    condition = alltrue([
      for e in var.transit_gateway_route_tables :
      length(coalesce(e.cidrs, [])) == length(distinct(coalesce(e.cidrs, []))) &&
      alltrue([for cidr in coalesce(e.cidrs, []) : can(cidrhost(cidr, 0))])
    ])
    error_message = "Every cidr on a route table entry has to be a distinct CIDR block in prefix notation, because one resource is written per table and destination."
  }

  assert {
    condition     = alltrue([for t in local.tgw_route_tables : !t.propagate || !contains(t.cidrs, var.vpc_cidr)])
    error_message = "Propagation already writes this VPC's CIDR onto the table, so a static route for the same destination on the same table fails at apply with RouteAlreadyExists. Remove the cidr from that entry, or set propagate to false so the route is written by hand."
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
