terraform {
  required_version = ">= 1.5.0"

  # Local state for now. Move to an S3 backend when this repo is shared.
  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
