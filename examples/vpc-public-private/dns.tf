# DNS forwarding to a resolver in an upstream VPC. The inbound resolver endpoint
# on the upstream side is owned by whoever runs that VPC; this creates the
# outbound endpoint here plus one FORWARD rule per domain, or just the rules when
# an existing endpoint ARN is supplied.
locals {
  dns_forwarding_enabled   = var.enable_dns_forwarding
  create_resolver_endpoint = local.dns_forwarding_enabled && var.resolver_endpoint_arn == null

  # Default to the first two subnets, which is what Route 53 Resolver wants for
  # an endpoint (two ip_address blocks, in different AZs for resilience).
  resolver_subnets = coalesce(var.resolver_endpoint_subnets, slice(local.private_subnets, 0, 2))

  resolver_security_group_ids = concat(
    var.resolver_security_group_ids,
    local.create_resolver_endpoint && var.create_resolver_security_group ? [aws_security_group.resolver[0].id] : [],
  )

  resolver_endpoint_id = coalesce(var.resolver_endpoint_arn, try(aws_route53_resolver_endpoint.outbound[0].id, null))
}

check "dns_forwarding_config" {
  assert {
    condition     = !var.enable_dns_forwarding || length(var.resolver_query_domains) > 0
    error_message = "resolver_query_domains must contain at least one domain when enable_dns_forwarding is true."
  }

  assert {
    condition     = !var.enable_dns_forwarding || var.resolver_endpoint_arn != null || length(local.resolver_subnets) >= 2
    error_message = "Route 53 Resolver endpoints need at least two ip_address blocks, so resolver_endpoint_subnets must list at least two subnets (or pass an existing resolver_endpoint_arn)."
  }
}

resource "aws_security_group" "resolver" {
  count = local.create_resolver_endpoint && var.create_resolver_security_group ? 1 : 0

  name   = "${var.vpc_name}-resolver"
  vpc_id = module.vpc.vpc_id

  # Queries reaching the endpoint from inside the VPC.
  ingress {
    description = "DNS (TCP) from within the VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "DNS (UDP) from within the VPC"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Traffic the endpoint sends onward, i.e. to the upstream resolver. Narrow this
  # to the upstream VPC CIDR when you know it.
  egress {
    description = "DNS (TCP) to the upstream resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = var.resolver_egress_cidr_blocks
  }

  egress {
    description = "DNS (UDP) to the upstream resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = var.resolver_egress_cidr_blocks
  }

  tags = local.common_tags
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = local.create_resolver_endpoint ? 1 : 0

  name               = "${var.vpc_name}-resolver-outbound"
  direction          = "OUTBOUND"
  security_group_ids = local.resolver_security_group_ids

  dynamic "ip_address" {
    for_each = local.resolver_subnets

    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.common_tags, { Name = "${var.vpc_name}-resolver-outbound" })
}

resource "aws_route53_resolver_rule" "forward" {
  for_each = local.dns_forwarding_enabled ? toset(var.resolver_query_domains) : toset([])

  name                 = "${var.vpc_name}-forward-${each.key}"
  rule_type            = "FORWARD"
  domain_name          = each.key
  resolver_endpoint_id = local.resolver_endpoint_id

  tags = merge(local.common_tags, { Name = "${var.vpc_name}-forward-${each.key}" })
}

# Rules are not associated automatically; this is what makes the VPC actually use them.
resource "aws_route53_resolver_rule_association" "forward" {
  for_each = local.dns_forwarding_enabled ? toset(var.resolver_query_domains) : toset([])

  resolver_rule_id = aws_route53_resolver_rule.forward[each.key].id
  vpc_id           = module.vpc.vpc_id
}
