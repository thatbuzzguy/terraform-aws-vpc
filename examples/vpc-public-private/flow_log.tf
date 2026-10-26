module "flow_log" {
  source  = "terraform-aws-modules/vpc/aws//modules/flow-log"
  version = "~> 6.7"

  name   = var.vpc_name
  vpc_id = module.vpc.vpc_id

  traffic_type                           = "ALL"
  max_aggregation_interval               = 600
  cloudwatch_log_group_retention_in_days = 90

  tags = local.common_tags
}
