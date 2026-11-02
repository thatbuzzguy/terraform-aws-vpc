# ECS needs a path to ECR, CloudWatch Logs, and the ECS control plane. In a VPC with no
# public subnets there is no NAT gateway, so the interface endpoints are the only way tasks
# reach those services, and the S3 gateway endpoint is what lets ECR image layers download.
locals {
  create_endpoints = var.enable_endpoints && length(var.endpoints) > 0

  # Interface endpoints need ENIs in subnets; gateway endpoints only write a route onto a
  # route table, so they need neither subnets nor a security group.
  endpoint_subnets      = coalesce(var.endpoint_subnets, module.vpc.private_subnets)
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
    condition     = !var.enable_endpoints || length(coalesce(var.endpoint_subnets, [])) > 0 || length(var.private_subnets) > 0
    error_message = "Interface endpoints need at least one subnet in this VPC to put an ENI in; endpoint_subnets is empty and there are no private subnets to fall back to."
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
