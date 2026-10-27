variable "aws_region" {
  description = "AWS region to deploy resources in."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name applied to resources created by this repository as a tag."
  type        = string
  default     = "terraform-infra"
}

variable "environment" {
  description = "Environment name used for tagging and resource names."
  type        = string
  default     = "dev"
}

variable "vpc_name" {
  description = "Name of the private-only VPC."
  type        = string
  default     = "tgw-example-vpc"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Must be routable from the transit gateway."
  type        = string
  default     = "10.1.0.0/16"
}

variable "enable_ipv6" {
  description = "Request an IPv6 CIDR block for the VPC. When `ipv6_cidr` is not set, AWS assigns a /56 from the Amazon pool."
  type        = bool
  default     = false
}

variable "ipv6_cidr" {
  description = "Explicit IPv6 CIDR block (/56) for the VPC. Leave null to let AWS assign one when `enable_ipv6` is true."
  type        = string
  default     = null
}

variable "intra_subnet_ipv6_prefixes" {
  description = "IPv6 /64 prefix offsets for the intra subnets, unique within the VPC's /56. Only used when `enable_ipv6` is true."
  type        = list(string)
  default     = ["0", "1", "2"]
}

variable "assign_ipv6_address_on_creation" {
  description = "Assign an IPv6 address to network interfaces created in each subnet (requires `enable_ipv6`)."
  type        = bool
  default     = false
}

# DNS resolver forwarding to an upstream VPC.
variable "enable_dns_forwarding" {
  description = "Create a Route 53 Resolver outbound endpoint and a FORWARD rule for `resolver_query_domains`."
  type        = bool
  default     = false
}

variable "resolver_query_domains" {
  description = "Domains forwarded to the upstream resolver. Required when `enable_dns_forwarding` is true."
  type        = list(string)
  default     = []
}

variable "resolver_endpoint_arn" {
  description = "ARN of an existing resolver endpoint to attach the forward rule to. Leave null to create an outbound endpoint in this VPC."
  type        = string
  default     = null
}

variable "resolver_endpoint_subnets" {
  description = "Subnets the outbound resolver endpoint is placed in. Defaults to the first two intra subnets of this VPC."
  type        = list(string)
  default     = null
}

variable "resolver_security_group_ids" {
  description = "Security groups attached to the outbound resolver endpoint. The upstream inbound endpoint must allow these source IPs."
  type        = list(string)
  default     = []
}

variable "create_resolver_security_group" {
  description = "Create a security group for the outbound resolver endpoint allowing DNS from inside the VPC."
  type        = bool
  default     = true
}

variable "resolver_egress_cidr_blocks" {
  description = "Ranges the resolver endpoint may send DNS traffic to. Narrow to the upstream VPC CIDR when known."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Static inputs for resources this account cannot read. An ID or an ARN is accepted
# and transit_gateway.tf reduces the ARN to the ID the resources take, because
# `aws ec2 get-transit-gateway-default-route-table-id` prints an ARN.
variable "transit_gateway_id" {
  description = "Transit gateway ID (tgw-xxxxxxxxxxxxxxxxxxx), or its ARN when it is owned by another account."
  type        = string

  validation {
    condition     = can(regex("^(tgw-[0-9a-f]+|arn:aws[a-z-]*:ec2:[a-z0-9-]+:[0-9]{12}:transit-gateway/tgw-[0-9a-f]+)$", var.transit_gateway_id))
    error_message = "transit_gateway_id must be a transit gateway ID or its ARN, not an attachment ID."
  }
}

variable "transit_gateway_route_table_id" {
  description = "Transit gateway route table ID (tgw-rt-xxxxxxxxxxxxxxxxxxx), or its ARN when it is owned by another account. Propagation requires the TGW owner to allow it."
  type        = string

  validation {
    condition     = can(regex("^(tgw-rt-[0-9a-f]+|arn:aws[a-z-]*:ec2:[a-z0-9-]+:[0-9]{12}:transit-gateway-route-table/tgw-rt-[0-9a-f]+)$", var.transit_gateway_route_table_id))
    error_message = "transit_gateway_route_table_id must be a route table ID or its ARN."
  }
}

# Set when the transit gateway and route table are owned by another account and
# shared into this one through RAM: the data sources cannot read them there, so the
# static inputs above are used as given. The share still has to be accepted here
# (automatic inside an AWS Organization, otherwise in the RAM console), because AWS
# checks it when the association is created.
variable "use_static_tgw_ids" {
  description = "Skip the data source reads and use transit_gateway_id / transit_gateway_route_table_id exactly as supplied. Set for a transit gateway shared into this account."
  type        = bool
  default     = false
}

variable "tgw_region" {
  description = "Region the transit gateway is in, when it differs from `aws_region`. Only used by the data source reads, since a VPC attachment cannot cross regions."
  type        = string
  default     = null
}

variable "replace_existing_association" {
  description = "Drop the attachment's current route table association before creating this one. Needed when the TGW auto-associates new attachments with its default route table, which is the usual case for both owned and shared TGWs."
  type        = bool
  default     = true
}

variable "enable_tgw_association" {
  description = "Whether to associate the VPC attachment with the transit gateway route table."
  type        = bool
  default     = true
}

variable "enable_tgw_propagation" {
  description = "Whether to propagate the VPC attachment's routes (the VPC CIDR) to the transit gateway route table."
  type        = bool
  default     = true
}

variable "default_route_to_tgw" {
  description = "Whether to add a 0.0.0.0/0 route on the intra route table pointing at the transit gateway."
  type        = bool
  default     = true
}
