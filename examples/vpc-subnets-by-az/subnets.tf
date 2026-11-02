locals {
  all_subnets = concat(
    [for s in var.private_subnets : merge(s, { tier = "private" })],
    [for s in var.public_subnets : merge(s, { tier = "public" })],
  )

  # The module places a subnet in `element(var.azs, index)`, using the same azs list for
  # every tier. AZ assignment is therefore positional: a subnet gets whatever azs holds at
  # its position, and there is no per-tier AZ mapping. So azs is built from the subnet
  # entries themselves, taking the AZ of the first tier that has an entry at each position,
  # and the checks below make every tier agree with that order.
  max_subnet_count = max(length(var.private_subnets), length(var.public_subnets), 1)

  azs = [
    for i in range(local.max_subnet_count) : coalesce(
      try(var.private_subnets[i].az, null),
      try(var.public_subnets[i].az, null),
    )
  ]

  # Each entry has to sit at the position its own az implies. Two subnets in the same AZ is
  # fine: that AZ then simply appears twice in azs.
  private_az_ok = [for i, s in var.private_subnets : s.az == local.azs[i]]
  public_az_ok  = [for i, s in var.public_subnets : s.az == local.azs[i]]

  private_subnets      = [for s in var.private_subnets : s.cidr]
  private_subnet_names = [for s in var.private_subnets : s.name]
  public_subnets       = [for s in var.public_subnets : s.cidr]
  public_subnet_names  = [for s in var.public_subnets : s.name]

  common_tags = {
    Environment = var.environment
  }
}

check "subnet_layout" {
  assert {
    condition     = length(var.private_subnets) > 0
    error_message = "private_subnets needs at least one subnet; the private tier is what this example is built around."
  }

  assert {
    condition     = alltrue([for s in local.all_subnets : s.name != "" && can(cidrhost(s.cidr, 0))])
    error_message = "Every subnet needs a name and a CIDR block in prefix notation. Terraform cannot test whether a CIDR is inside vpc_cidr, so AWS is the one that rejects it, at apply."
  }

  assert {
    condition     = length(distinct([for s in local.all_subnets : s.name])) == length(local.all_subnets)
    error_message = "Subnet names must be unique across both tiers, because the Name tag is the only thing that tells the subnets apart."
  }

  assert {
    condition     = length(distinct([for s in local.all_subnets : s.cidr])) == length(local.all_subnets)
    error_message = "Subnet CIDRs must be unique across both tiers."
  }

  assert {
    condition     = alltrue(local.private_az_ok) && alltrue(local.public_az_ok)
    error_message = "The module assigns each subnet the AZ at its position in azs, so a subnet can only be in the AZ its list position implies. Reorder the subnet lists so the tiers agree position by position; a shorter tier can stop early but cannot skip a position."
  }

  assert {
    condition     = !var.enable_nat_gateway || length(var.public_subnets) > 0
    error_message = "A NAT gateway is created in a public subnet, so enable_nat_gateway needs at least one entry in public_subnets. Without a public tier the interface endpoints are the only egress path."
  }

  assert {
    condition     = !var.one_nat_gateway_per_az || length(var.public_subnets) >= local.max_subnet_count
    error_message = "one_nat_gateway_per_az makes the module skip the public tier when it has fewer entries than azs, so the public tier must be at least as long as the longest tier."
  }
}
