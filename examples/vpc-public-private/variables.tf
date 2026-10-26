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
  description = "Name of the example VPC."
  type        = string
  default     = "example-vpc"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
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

variable "private_subnet_ipv6_prefixes" {
  description = "IPv6 /64 prefix offsets for the private subnets, unique within the VPC's /56. Only used when `enable_ipv6` is true."
  type        = list(string)
  default     = ["0", "1", "2"]
}

variable "public_subnet_ipv6_prefixes" {
  description = "IPv6 /64 prefix offsets for the public subnets, unique within the VPC's /56 and different from the private ones. Only used when `enable_ipv6` is true."
  type        = list(string)
  default     = ["4", "5", "6"]
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
  description = "Subnets the outbound resolver endpoint is placed in. Defaults to the first two subnets of this VPC."
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
