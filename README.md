# terraform-infra

Terraform configuration for AWS infrastructure. Each directory under `examples/`
is a standalone root module with its own provider block, its own state file, and
its own `.terraform.lock.hcl`.

| Directory | What it creates |
| --- | --- |
| `examples/vpc-public-private` | Public + private VPC, single NAT gateway, gateway endpoints, flow logs |
| `examples/vpc-transit-gateway` | Private-only (intra) VPC connected to a pre-existing transit gateway |

## Running an example

```bash
cd examples/<name>
terraform init
terraform plan
terraform apply
```

Credentials come from the standard AWS provider sources (environment variables,
AWS profile, or instance metadata). Nothing is hard-coded in this repo.

## Conventions

- Provider `hashicorp/aws` constrained to `~> 6.0`; the VPC module is pinned to
  `~> 6.7` (module v6 requires provider >= 6.28).
- Lock files are committed for reproducible installs.
- Variable files are gitignored; `*.tfvars.example` templates are committed.
- State is local for these examples. Move `backend "local"` to an S3 backend
  before any of this is shared with another person, and re-run with
  `-migrate-state`.
