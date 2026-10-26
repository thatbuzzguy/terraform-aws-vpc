output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the VPC (null when `enable_ipv6` is false)."
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "public_subnets_ipv6_cidr_blocks" {
  description = "IPv6 /64 blocks of the public subnets."
  value       = module.vpc.public_subnets_ipv6_cidr_blocks
}

output "private_subnets_ipv6_cidr_blocks" {
  description = "IPv6 /64 blocks of the private subnets."
  value       = module.vpc.private_subnets_ipv6_cidr_blocks
}

output "public_subnets" {
  description = "Public subnet IDs."
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnets
}

output "private_route_table_ids" {
  description = "Private route table IDs (used by the gateway endpoints)."
  value       = module.vpc.private_route_table_ids
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs."
  value       = module.vpc.natgw_ids
}

output "nat_gateway_public_ip" {
  description = "Public Elastic IP used by the NAT gateway."
  value       = try(module.vpc.nat_public_ips[0], null)
}

output "flow_log_arn" {
  description = "ARN of the VPC flow log."
  value       = module.flow_log.arn
}

output "flow_log_cloudwatch_log_group" {
  description = "CloudWatch log group receiving flow logs."
  value       = module.flow_log.cloudwatch_log_group_name
}

output "resolver_endpoint_id" {
  description = "ID of the outbound resolver endpoint (null when forwarding is off or an existing endpoint is used)."
  value       = try(aws_route53_resolver_endpoint.outbound[0].id, null)
}

output "resolver_rules" {
  description = "FORWARD resolver rules keyed by query domain (empty when forwarding is off)."
  value       = { for domain, rule in aws_route53_resolver_rule.forward : domain => rule.id }
}

output "resolver_rule_associations" {
  description = "Associations between the forward rules and this VPC."
  value       = { for domain, association in aws_route53_resolver_rule_association.forward : domain => association.id }
}

output "resolver_security_group_id" {
  description = "Security group used by the outbound resolver endpoint. Share these source IPs with the upstream resolver owner."
  value       = try(aws_security_group.resolver[0].id, null)
}

output "endpoints" {
  description = "VPC endpoints created by the endpoints sub-module."
  value       = module.endpoints.endpoints
}
