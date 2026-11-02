# One flow log for the whole VPC, which is the coarse option: a record says which interface it
# belonged to, so the VLAN is identified after the fact rather than by having one flow log per
# subnet. CloudWatch is the default destination; S3 is the cheaper one to keep for long.
#
# The role this creates is for CloudWatch or Firehose delivery. An S3 destination does not need
# a role at all, so `create_flow_log_iam_role` is ignored there. A TGW-scoped flow log would be
# a different resource, on the attachment rather than the VPC, and is not what this example does.
module "flow_log" {
  source  = "terraform-aws-modules/vpc/aws//modules/flow-log"
  version = "~> 6.7"

  create = var.create_flow_log

  name   = var.vpc_name
  vpc_id = module.vpc.vpc_id

  traffic_type             = var.flow_log_traffic_type
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  log_destination_type = var.flow_log_destination_type
  log_destination      = var.flow_log_destination

  create_cloudwatch_log_group            = var.create_flow_log_log_group
  cloudwatch_log_group_retention_in_days = var.flow_log_retention_in_days

  create_iam_role = var.create_flow_log_iam_role
  iam_role_arn    = var.flow_log_iam_role_arn

  tags = local.common_tags

  # The submodule puts tags on the log group and the role too, so this is what distinguishes a
  # flow log delivered to a shared destination from one created here.
  flow_log_tags = { Scope = "vpc" }
}

check "flow_log_config" {
  assert {
    condition     = !var.create_flow_log || contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], var.flow_log_destination_type)
    error_message = "flow_log_destination_type must be cloud-watch-logs, s3, or kinesis-data-firehose."
  }

  assert {
    condition     = !var.create_flow_log || contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT, or ALL."
  }

  assert {
    condition     = !var.create_flow_log || contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval is 60 or 600 seconds; anything else is rejected by AWS at apply."
  }

  assert {
    condition = (
      !var.create_flow_log ||
      var.flow_log_destination != null ||
      (var.flow_log_destination_type == "cloud-watch-logs" && var.create_flow_log_log_group)
    )
    error_message = "The flow log needs somewhere to write: flow_log_destination is the existing log group or bucket ARN, and a CloudWatch destination can instead use a log group created here."
  }

  assert {
    condition     = !var.create_flow_log || var.flow_log_destination_type == "s3" || var.create_flow_log_iam_role || var.flow_log_iam_role_arn != null
    error_message = "A CloudWatch or Firehose destination needs a role that vpc-flow-logs.amazonaws.com can assume; either create one here or pass flow_log_iam_role_arn."
  }

  assert {
    condition     = !var.create_flow_log || var.flow_log_retention_in_days >= 1
    error_message = "flow_log_retention_in_days has to be at least 1 day; CloudWatch only accepts the published retention values, so check the number you use against that list."
  }
}
