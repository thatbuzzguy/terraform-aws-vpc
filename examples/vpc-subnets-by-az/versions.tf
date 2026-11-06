terraform {
  # 1.9 for the optional() attributes in the transit_gateway_route_tables objects.
  required_version = ">= 1.9.0"

  # Local state for now. Move to an S3 backend when this repo is shared.
  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
