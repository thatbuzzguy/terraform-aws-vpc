# Private-only VPC connected to a pre-existing transit gateway

No public subnets, no internet gateway, no NAT gateway. Subnets are `intra`
subnets, whose only path out of the VPC is the TGW attachment.

## What it creates

- VPC `10.1.0.0/16` with three intra subnets in `us-west-2a/b/c`
- One intra route table, with `0.0.0.0/0` pointing at the transit gateway
- TGW VPC attachment using the intra subnets, with DNS support enabled
- Association + propagation against the pre-existing TGW route table
- S3 and DynamoDB gateway endpoints on the intra route table (no paid egress path)

## Dual-stack (optional)

Both CIDR families are variables:

```bash
terraform plan \
  -var 'vpc_cidr=10.1.0.0/16' \
  -var 'enable_ipv6=true' \
  -var 'ipv6_cidr=2600:1f1c:abcd:ef00::/56'
```

- `vpc_cidr` is IPv4; `ipv6_cidr` is optional and AWS assigns a /56 when it is
  left null and `enable_ipv6 = true`.
- `intra_subnet_ipv6_prefixes` needs one entry per intra subnet.
- `assign_ipv6_address_on_creation = true` gives ENIs in the subnets an IPv6
  address at launch.
- With IPv6 enabled, a `::/0` route is added on the intra route table pointing at
  the transit gateway. Since there is no egress-only internet gateway in this
  topology, the TGW is the only IPv6 path, and its route table must have a
  matching IPv6 route back to the VPC's /56.

## DNS forwarding to an upstream resolver (optional)

`dns.tf` adds a Route 53 Resolver setup, all driven by variables:

| Variable | Purpose |
| --- | --- |
| `enable_dns_forwarding` | Turn the whole block on (default `false`) |
| `resolver_query_domains` | Domains to forward, one FORWARD rule per domain |
| `resolver_endpoint_arn` | Use an existing endpoint instead of creating one |
| `resolver_endpoint_subnets` | Where the outbound endpoint lives (defaults to the first two intra subnets) |
| `resolver_security_group_ids` | Existing groups to attach |
| `create_resolver_security_group` | Create one allowing DNS from inside the VPC (default `true`) |
| `resolver_egress_cidr_blocks` | Where the endpoint may send DNS traffic; narrow to the upstream CIDR |

```bash
terraform plan \
  -var 'enable_dns_forwarding=true' \
  -var 'resolver_query_domains=["corp.example.internal"]' \
  -var 'resolver_egress_cidr_blocks=["10.9.0.0/16"]'
```

In this topology the path to the upstream resolver is the transit gateway, so the
forwarding only works if the TGW route table can route to the upstream VPC. The
upstream inbound endpoint is owned by the other team; they must allow this
endpoint's source IPs, which the `resolver_security_group_id` output reports.

Resolver endpoints are not free (roughly $0.275 per endpoint per hour), so leave
`enable_dns_forwarding` off unless a domain actually needs forwarding.

## Running it

```bash
cd examples/vpc-transit-gateway
cp example.auto.tfvars.example example.auto.tfvars   # fill in the real TGW IDs
terraform init
terraform plan
terraform apply
```

`transit_gateway_id` and `transit_gateway_route_table_id` have no defaults; the
data sources fail the plan if the IDs do not exist, which is a useful sanity check.

## Things to watch

- Propagation only works if the TGW route table allows it. If your TGW is managed
  by another team, they usually own the return route; set
  `enable_tgw_propagation = false` and ask them to add a static route for the VPC CIDR.
- The TGW must have a route back to `10.1.0.0/16`, otherwise traffic leaves the
  VPC and never comes back.
- DNS from the intra subnets resolves through the AWS resolver, which needs the
  TGW path back; `dns_support = "enable"` on the attachment is what makes that work.
