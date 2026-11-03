# ECS needs a path to ECR, CloudWatch Logs, and the ECS control plane. In a VPC with no
# public subnets there is no NAT gateway, so the interface endpoints are the only way tasks
# reach those services, and the S3 gateway endpoint is what lets ECR image layers download.
locals {
  create_endpoints = var.enable_endpoints && length(var.endpoints) > 0

  # Interface endpoints need ENIs in subnets; gateway endpoints only write a route onto a
  # route table, so they need neither subnets nor a security group.
  #
  # An interface endpoint takes one subnet per AZ, so the private tier cannot be passed through
  # as it is when it has two subnets in the same AZ: CreateVpcEndpoint fails at apply with
  # DuplicateSubnetsInSameZone. The default is the first subnet in each AZ instead, which still
  # serves that whole AZ, because a flow from any subnet in the VPC resolves to the endpoint ENI.
  # Position i of module.vpc.private_subnets is subnet i, so position carries the AZ.
  default_endpoint_subnets = [
    for i, s in var.private_subnets : module.vpc.private_subnets[i]
    if index([for x in var.private_subnets : x.az], s.az) == i
  ]

  # A list supplied here is used as it is: Terraform does not know which AZ a subnet ID is in at
  # plan time, so it has to hold at most one subnet per AZ.
  endpoint_subnets      = coalesce(var.endpoint_subnets, local.default_endpoint_subnets)
  endpoint_route_tables = coalesce(var.endpoint_route_tables, module.vpc.private_route_table_ids)

  # Gateway services write a prefix-list route onto a route table; everything else is an
  # interface endpoint with ENIs in subnets. Terraform needs both branches of a ternary to
  # be the same object type, so each type gets its own map and they are merged.
  endpoints = merge(
    {
      for service in var.endpoints : service => {
        service         = service
        service_type    = "Gateway"
        route_table_ids = local.endpoint_route_tables
      } if contains(var.gateway_endpoints, service)
    },
    {
      for service in var.endpoints : service => {
        service             = service
        service_type        = "Interface"
        subnet_ids          = local.endpoint_subnets
        private_dns_enabled = var.endpoint_private_dns_enabled
      } if !contains(var.gateway_endpoints, service)
    },
  )
}

check "endpoint_config" {
  assert {
    condition     = !var.enable_endpoints || length(var.endpoints) > 0
    error_message = "enable_endpoints is true but endpoints is empty, so nothing would be created."
  }

  assert {
    condition     = !var.enable_endpoints || length(coalesce(var.endpoint_subnets, var.private_subnets)) > 0
    error_message = "Interface endpoints need at least one subnet in this VPC to put an ENI in; endpoint_subnets is empty and there are no private subnets to fall back to."
  }

  # Only the supplied list can be checked, and only as an upper bound: one subnet per AZ means
  # the list cannot be longer than the number of distinct AZs. Two entries in the same AZ cannot
  # be seen from IDs at plan time, so that one is left to AWS.
  assert {
    condition     = !var.enable_endpoints || var.endpoint_subnets == null || length(var.endpoint_subnets) <= length(distinct(local.azs))
    error_message = "Interface endpoints take one subnet per availability zone, so endpoint_subnets cannot have more entries than this VPC has distinct AZs. Without endpoint_subnets the default already picks one per AZ, which is what lets the private tier have several subnets in the same AZ."
  }

  assert {
    condition     = !var.enable_endpoints || var.enable_dns_support
    error_message = "Interface endpoints with private DNS need enable_dns_support, otherwise the service DNS names do not resolve inside the VPC."
  }
}

module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  create = local.create_endpoints
  vpc_id = module.vpc.vpc_id

  create_security_group = var.create_endpoint_security_group
  security_group_name   = "${var.vpc_name}-endpoints"

  # Interface endpoint ENIs only accept HTTPS. Gateway endpoints are route table entries
  # and ignore the security group.
  security_group_ids = var.endpoint_security_group_ids

  security_group_rules = {
    ingress_https = {
      description = "HTTPS from within the VPC"
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  endpoints = local.endpoints

  tags = local.common_tags
}
