output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC. The TGW route table must be able to route this range back."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the VPC (null when `enable_ipv6` is false). The TGW route table needs an IPv6 route back to it."
  value       = module.vpc.vpc_ipv6_cidr_block
}

output "intra_subnets_ipv6_cidr_blocks" {
  description = "IPv6 /64 blocks of the intra subnets."
  value       = module.vpc.intra_subnets_ipv6_cidr_blocks
}

output "intra_subnets" {
  description = "Intra subnet IDs (the attachment subnet list)."
  value       = module.vpc.intra_subnets
}

output "intra_route_table_ids" {
  description = "Intra route table IDs (used by the TGW default route and gateway endpoints)."
  value       = module.vpc.intra_route_table_ids
}

output "transit_gateway_id" {
  description = "ID of the pre-existing transit gateway."
  value       = local.tgw_id
}

output "transit_gateway_route_table_id" {
  description = "ID of the pre-existing transit gateway route table."
  value       = local.tgw_route_table_id
}

output "transit_gateway_attachment_id" {
  description = "ID of the VPC attachment created on the transit gateway."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "transit_gateway_association_id" {
  description = "Association ID between the attachment and the TGW route table."
  value       = try(aws_ec2_transit_gateway_route_table_association.this[0].id, null)
}

output "transit_gateway_propagation_id" {
  description = "Propagation ID between the attachment and the TGW route table."
  value       = try(aws_ec2_transit_gateway_route_table_propagation.this[0].id, null)
}

output "default_route_to_tgw_id" {
  description = "ID of the intra default route pointing at the transit gateway."
  value       = try(aws_route.intra_default_to_tgw[0].id, null)
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
