# Public + private VPC example

Standard tiered VPC with a single NAT gateway, gateway endpoints, and flow logs.

## What it creates

- VPC `10.0.0.0/16` with public subnets (`10.0.101-103.0/24`) and private
  subnets (`10.0.1-3.0/24`) in `us-west-2a/b/c`
- One public and one private route table, single NAT gateway + EIP
- Internet gateway with the public default route
- S3 and DynamoDB gateway endpoints on the private route table
- VPC flow logs to a CloudWatch log group (90-day retention) with the IAM role

## Dual-stack (optional)

CIDR ranges are variables, not literals:

```bash
terraform plan \
  -var 'vpc_cidr=10.0.0.0/16' \
  -var 'enable_ipv6=true' \
  -var 'ipv6_cidr=2600:1f1c:abcd:ef00::/56'
```

- `vpc_cidr` is the IPv4 range; subnets are derived from it with `cidrsubnet()`.
- `ipv6_cidr` is optional. With `enable_ipv6 = true` and `ipv6_cidr` unset, AWS
  assigns a /56 from the Amazon pool, so the output is only known at apply.
- `private_subnet_ipv6_prefixes` and `public_subnet_ipv6_prefixes` must each have
  one entry per subnet (three here) and must not overlap, since both sets draw
  from the same /56. Defaults: private `0,1,2`, public `4,5,6`.
- `assign_ipv6_address_on_creation = true` makes ENIs in the subnets receive an
  IPv6 address at launch.
- When IPv6 is on, the module adds an egress-only internet gateway and the `::/0`
  route on the public route table.

## DNS forwarding to an upstream resolver (optional)

`dns.tf` adds a Route 53 Resolver setup, all driven by variables:

| Variable | Purpose |
| --- | --- |
| `enable_dns_forwarding` | Turn the whole block on (default `false`) |
| `resolver_query_domains` | Domains to forward, one FORWARD rule per domain |
| `resolver_endpoint_arn` | Use an existing endpoint instead of creating one |
| `resolver_endpoint_subnets` | Where the outbound endpoint lives (defaults to the first two subnets) |
| `resolver_security_group_ids` | Existing groups to attach |
| `create_resolver_security_group` | Create one allowing DNS from inside the VPC (default `true`) |
| `resolver_egress_cidr_blocks` | Where the endpoint may send DNS traffic; narrow to the upstream CIDR |

```bash
terraform plan \
  -var 'enable_dns_forwarding=true' \
  -var 'resolver_query_domains=["corp.example.internal"]' \
  -var 'resolver_egress_cidr_blocks=["10.9.0.0/16"]'
```

The inbound endpoint in the upstream VPC is not created here - its owner has to
allow this endpoint's source IPs on their inbound endpoint. Two practical notes:

- Forwarding only works if there is a network path from the endpoint subnets to
  the upstream resolver. In this example that means VPC peering or a transit
  gateway attachment; a NAT gateway path will not reach a private upstream VPC.
- Resolver endpoints are not free (roughly $0.275 per endpoint per hour), and
  queries past the first billion per month are billed. Only enable it when you
  actually need to forward a domain.

## Running it

```bash
cd examples/vpc-public-private
terraform init
terraform plan
terraform apply
```

The example uses `single_nat_gateway = true` to keep cost down. For production,
set `single_nat_gateway = false` (one NAT gateway per private subnet) or
`one_nat_gateway_per_az = true`.

Cost note: the NAT gateway and its EIP are the only billable items here
(~$32/month plus processing); subnets, route tables, IGW, gateway endpoints, and
flow logs themselves are free or near-free.
