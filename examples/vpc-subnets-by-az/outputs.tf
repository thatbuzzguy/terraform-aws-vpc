output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "azs" {
  description = "AZ order the module used, position by position. Derived from the subnet entries, so a repeated AZ means several subnets in that AZ."
  value       = local.azs
}

output "private_subnets" {
  description = "Private subnets keyed by the name given to them, with CIDR, AZ, and the ID assigned at apply."
  value = {
    for i, s in var.private_subnets : s.name => {
      tier = "private"
      cidr = s.cidr
      az   = s.az
      id   = try(module.vpc.private_subnets[i], null)
    }
  }
}

output "public_subnets" {
  description = "Public subnets keyed by name, empty when the public tier is not used."
  value = {
    for i, s in var.public_subnets : s.name => {
      tier = "public"
      cidr = s.cidr
      az   = s.az
      id   = try(module.vpc.public_subnets[i], null)
    }
  }
}

output "private_route_table_ids" {
  description = "Private route tables. One with single_nat_gateway, one per private subnet otherwise."
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "Public route tables (empty when the public tier is not used)."
  value       = module.vpc.public_route_table_ids
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (empty when enable_nat_gateway is false)."
  value       = module.vpc.natgw_ids
}

output "nat_gateway_public_ip" {
  description = "Public Elastic IP used by the NAT gateway."
  value       = try(module.vpc.nat_public_ips[0], null)
}

output "transit_gateway_id" {
  description = "ID of the pre-existing transit gateway, or the ID an ARN reduced to (null when enable_transit_gateway is false)."
  value       = local.tgw_id
}

output "transit_gateway_route_table_id" {
  description = "ID of the pre-existing transit gateway route table (null when enable_transit_gateway is false)."
  value       = local.tgw_route_table_id
}

output "transit_gateway_attachment_id" {
  description = "ID of the VPC attachment (null when enable_transit_gateway is false)."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, null)
}

output "transit_gateway_subnets" {
  description = "Subnets the attachment uses, after the default is resolved."
  value       = local.tgw_subnets
}

output "transit_gateway_association_id" {
  description = "Association ID between the attachment and the TGW route table."
  value       = try(aws_ec2_transit_gateway_route_table_association.this[0].id, null)
}

output "transit_gateway_propagation_id" {
  description = "Propagation ID between the attachment and the TGW route table."
  value       = try(aws_ec2_transit_gateway_route_table_propagation.this[0].id, null)
}

output "transit_gateway_default_routes" {
  description = "Default routes pointing at the transit gateway, keyed by route table ID (empty when default_route_to_tgw is false)."
  value = {
    for route in aws_route.private_default_to_tgw : route.route_table_id => route.id
  }
}

output "endpoints" {
  description = "VPC endpoints keyed by service name, empty when enable_endpoints is false."
  value = {
    for service, endpoint in module.endpoints.endpoints : service => {
      type            = endpoint.vpc_endpoint_type
      private_dns     = try(endpoint.private_dns_enabled, null)
      id              = endpoint.id
      arn             = endpoint.arn
      dns_name        = try(endpoint.dns_entry[0].dns_name, null)
      subnet_ids      = try(endpoint.subnet_ids, [])
      route_table_ids = try(endpoint.route_table_ids, [])
    }
  }
}

output "endpoint_security_group_id" {
  description = "Security group attached to the interface endpoint ENIs."
  value       = module.endpoints.security_group_id
}

output "endpoint_subnets" {
  description = "Subnets the interface endpoints put ENIs in, after the default is resolved."
  value       = local.endpoint_subnets
}

output "endpoint_route_tables" {
  description = "Route tables the gateway endpoints write onto, after the default is resolved."
  value       = local.endpoint_route_tables
}

output "flow_log_id" {
  description = "ID of the VPC flow log (null when create_flow_log is false)."
  value       = module.flow_log.id
}

output "flow_log_arn" {
  description = "ARN of the VPC flow log."
  value       = module.flow_log.arn
}

output "flow_log_cloudwatch_log_group_name" {
  description = "CloudWatch log group receiving the flow log, null when an existing destination is used or the destination is not CloudWatch."
  value       = module.flow_log.cloudwatch_log_group_name
}

output "flow_log_iam_role_arn" {
  description = "Role used for delivery, null for an S3 destination or when an existing role was supplied."
  value       = module.flow_log.iam_role_arn
}
