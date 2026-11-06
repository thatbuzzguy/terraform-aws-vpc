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
  default     = "subnets-by-az-vpc"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Every subnet CIDR has to fall inside it."
  type        = string
  default     = "10.2.0.0/16"
}

# Subnets are declared one by one rather than generated from a netmask. The order of each
# list matters: the module assigns a subnet the AZ at its position, see subnets.tf.

variable "private_subnets" {
  description = "Private subnets, one object per subnet with an explicit name, CIDR, and AZ. The order of the list decides which AZ each subnet gets."
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = [
    { name = "app-2a", cidr = "10.2.1.0/24", az = "us-west-2a" },
    { name = "app-2b", cidr = "10.2.2.0/24", az = "us-west-2b" },
    { name = "app-2c", cidr = "10.2.3.0/24", az = "us-west-2c" },
  ]
}

variable "public_subnets" {
  description = "Public subnets, same shape as private_subnets. Leave empty for a private-only VPC, which is what makes the endpoints in endpoints.tf the only path out."
  type = list(object({
    name = string
    cidr = string
    az   = string
  }))
  default = []
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways. A NAT gateway has to sit in a public subnet, so this only works when public_subnets has entries; with no public tier the interface endpoints are the only egress path."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the whole private tier. With false the module makes one route table per private subnet, which is what you want when each subnet needs its own endpoint policy."
  type        = bool
  default     = true
}

variable "one_nat_gateway_per_az" {
  description = "One NAT gateway per AZ instead of per private subnet. Needs the public tier to have at least as many entries as the longest tier, otherwise the module skips the public subnets."
  type        = bool
  default     = false
}

variable "create_igw" {
  description = "Create an internet gateway. Only useful with a public tier; vpc.tf skips it when public_subnets is empty."
  type        = bool
  default     = true
}

variable "create_multiple_public_route_tables" {
  description = "One route table per public subnet instead of one for the whole tier."
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable the DNS resolver's hostnames for the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC. Leave on when endpoints are used: the interface endpoints' private DNS names only resolve through the VPC resolver."
  type        = bool
  default     = true
}

# VPC endpoints for ECS (optional).
variable "enable_endpoints" {
  description = "Create the endpoints listed in `endpoints`. In a private-only VPC these are the only way for tasks to reach the services, so it is on by default."
  type        = bool
  default     = true
}

variable "endpoints" {
  description = "Service names to create endpoints for, resolved with the aws_vpc_endpoint_service data source at plan time. A service that is not offered in the region fails the plan, so remove it from the list. Older regions may name the ECS agent endpoint `ecs.agent` (or `ecs.data`) instead of `ecs-agent`."
  type        = list(string)
  default     = ["ecs", "ecs-agent", "ecs-telemetry", "ecr.api", "ecr.dkr", "logs", "s3"]
}

variable "gateway_endpoints" {
  description = "Names in `endpoints` that are gateway type (written onto route tables) rather than interface type. Gateway endpoints are free, and ECR image layers live in S3, so s3 is on by default."
  type        = list(string)
  default     = ["s3"]
}

variable "endpoint_subnets" {
  description = "Subnets the interface endpoints put ENIs in. One subnet per AZ only, so the default is the first private subnet in each AZ rather than the whole private tier, which is what lets a tier hold several subnets in the same AZ. A list given here is used as it is, so it cannot repeat an AZ."
  type        = list(string)
  default     = null
}

variable "endpoint_route_tables" {
  description = "Route tables the gateway endpoints write their service prefix list onto. Defaults to the private route tables."
  type        = list(string)
  default     = null
}

variable "endpoint_private_dns_enabled" {
  description = "Resolve each service's public DNS name to its endpoint from inside the VPC. Needed for the ECS agent, which follows the private names ecs-a.<region>.amazonaws.com and ecs-t.<region>.amazonaws.com."
  type        = bool
  default     = true
}

# Transit gateway attachment (optional).
variable "enable_transit_gateway" {
  description = "Attach the VPC to a pre-existing transit gateway. Off by default, which is what leaves the endpoints as the only path out of the private VLANs."
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Transit gateway ID (tgw-xxxxxxxxxxxxxxxxxxx), or its ARN when it is owned by another account. Required when enable_transit_gateway is true."
  type        = string
  default     = null

  validation {
    condition     = var.transit_gateway_id == null || can(regex("^(tgw-[0-9a-f]+|arn:aws[a-z-]*:ec2:[a-z0-9-]+:[0-9]{12}:transit-gateway/tgw-[0-9a-f]+)$", var.transit_gateway_id))
    error_message = "transit_gateway_id must be a transit gateway ID or its ARN, not an attachment ID."
  }
}

# One entry per transit gateway route table the attachment is written to. Two entries is the
# usual case: the hub's table for this VPC, and a second one that has to be written by hand
# because it does not accept propagation from the spoke side.
variable "transit_gateway_route_tables" {
  description = "Transit gateway route tables, one object per table. `id` is the route table ID (tgw-rt-xxxxxxxxxxxxxxxxxxx), or its ARN when it is owned by another account. `associate` and `propagate` fall back to the flags below when an entry does not set them; `cidrs` are the destinations written as static routes on that table, which default to vpc_cidr for a table that is not propagated. At least one entry is required when enable_transit_gateway is true."
  type = list(object({
    id        = string
    associate = optional(bool)
    propagate = optional(bool)
    cidrs     = optional(list(string))
  }))
  default = []

  validation {
    condition     = alltrue([for e in var.transit_gateway_route_tables : can(regex("^(tgw-rt-[0-9a-f]+|arn:aws[a-z-]*:ec2:[a-z0-9-]+:[0-9]{12}:transit-gateway-route-table/tgw-rt-[0-9a-f]+)$", e.id))])
    error_message = "Every entry in transit_gateway_route_tables must be a route table ID or its ARN."
  }
}

# Set when the transit gateway and route table are owned by another account and shared into
# this one through RAM: the data sources cannot read them there, so the values above are used
# as given. The share still has to be accepted here (automatic inside an AWS Organization,
# otherwise in the RAM console), because AWS checks it when the association is created.
variable "use_static_tgw_ids" {
  description = "Skip the data source reads and use transit_gateway_id and the ids in transit_gateway_route_tables exactly as supplied. Set for a transit gateway shared into this account."
  type        = bool
  default     = false
}

variable "tgw_region" {
  description = "Region the transit gateway is in, when it differs from `aws_region`. Only used by the data source reads, since a VPC attachment cannot cross regions."
  type        = string
  default     = null
}

variable "transit_gateway_subnets" {
  description = "Subnets the VPC attachment uses. Defaults to the private subnets. Shared subnets cannot be used to create an attachment, only to use one."
  type        = list(string)
  default     = null
}

variable "tgw_dns_support" {
  description = "DNS resolution through the attachment. Leave enabled: it is what gives the private VLANs a resolver path back through the transit gateway."
  type        = bool
  default     = true
}

variable "replace_existing_association" {
  description = "Drop the attachment's current route table association before creating this one. Needed when the TGW auto-associates new attachments with its default route table, which is the usual case for both owned and shared TGWs."
  type        = bool
  default     = true
}

variable "enable_tgw_association" {
  description = "Whether to associate the VPC attachment with the transit gateway route tables. This is the default for an entry that does not set its own `associate`; a static route only forwards when the attachment is associated with the same table."
  type        = bool
  default     = true
}

variable "enable_tgw_propagation" {
  description = "Whether to propagate the VPC attachment's routes (the VPC CIDR) to the transit gateway route tables. This is the default for an entry that does not set its own `propagate`, and propagation needs the TGW owner to allow it. A table with propagate = false is where the routes are written by hand instead."
  type        = bool
  default     = true
}

variable "default_route_to_tgw" {
  description = "Whether to put a 0.0.0.0/0 route on each private route table pointing at the transit gateway. Cannot be combined with enable_nat_gateway, since both would write the same default route."
  type        = bool
  default     = true
}

variable "create_endpoint_security_group" {
  description = "Create a security group allowing HTTPS from inside the VPC to the interface endpoint ENIs."
  type        = bool
  default     = true
}

variable "endpoint_security_group_ids" {
  description = "Existing security groups to attach to the interface endpoints, in addition to the one created here."
  type        = list(string)
  default     = []
}

# VPC flow log (optional).
variable "create_flow_log" {
  description = "Create a flow log for the whole VPC. On by default, matching example 1."
  type        = bool
  default     = true
}

variable "flow_log_destination_type" {
  description = "Where the flow log writes: cloud-watch-logs, s3, or kinesis-data-firehose."
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], var.flow_log_destination_type)
    error_message = "flow_log_destination_type must be cloud-watch-logs, s3, or kinesis-data-firehose."
  }
}

variable "flow_log_destination" {
  description = "ARN of an existing destination: the CloudWatch log group when create_flow_log_log_group is false, the S3 bucket for an s3 destination, the Firehose delivery stream for kinesis-data-firehose. Ignored when the log group is created here."
  type        = string
  default     = null
}

variable "flow_log_traffic_type" {
  description = "Which traffic to capture: ACCEPT, REJECT, or ALL. REJECT is the one that shows a task trying to reach a service it has no endpoint for."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT, or ALL."
  }
}

variable "flow_log_max_aggregation_interval" {
  description = "Seconds a flow is aggregated before a record is written: 60 or 600."
  type        = number
  default     = 600
}

variable "flow_log_retention_in_days" {
  description = "Retention of the CloudWatch log group created here. CloudWatch only accepts the published values (1, 3, 5, 7, 14, 30, 60, 90, 120, ...)."
  type        = number
  default     = 90
}

variable "create_flow_log_log_group" {
  description = "Create the CloudWatch log group instead of delivering to an existing one. Only used by a cloud-watch-logs destination."
  type        = bool
  default     = true
}

variable "create_flow_log_iam_role" {
  description = "Create the role vpc-flow-logs.amazonaws.com assumes. Not needed for an S3 destination, and ignored there."
  type        = bool
  default     = true
}

variable "flow_log_iam_role_arn" {
  description = "Existing role ARN to use for delivery, when create_flow_log_iam_role is false."
  type        = string
  default     = null
}
