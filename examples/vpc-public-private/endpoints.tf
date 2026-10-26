module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  vpc_id = module.vpc.vpc_id

  # Gateway endpoints attach to route tables; interface endpoints need subnets
  # and a security group allowing HTTPS from inside the VPC.
  create_security_group = true
  security_group_name   = "${var.vpc_name}-endpoints"

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

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }

    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }

  tags = local.common_tags
}
