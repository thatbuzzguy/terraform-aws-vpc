# Private VLANs with explicit subnet names and CIDRs

Every subnet is declared as an entry - name, CIDR, AZ - rather than generated from a
netmask. Any number of subnets, any selection of AZs, a public tier only when you ask for
one, and optional VPC endpoints for ECS.

## What it creates

- VPC `10.2.0.0/16` with three private subnets named `app-2a`, `app-2b`, `app-2c` in
  `us-west-2a/b/c`, CIDRs `10.2.1-3.0/24`
- No public tier by default, so no internet gateway and no NAT gateway: one private route
  table, and the endpoints are the only path out
- Interface endpoints for `ecs`, `ecs-agent`, `ecs-telemetry`, `ecr.api`, `ecr.dkr`, and
  `logs`, with ENIs in the private subnets, plus the `s3` gateway endpoint on the private
  route table
- One security group allowing HTTPS from inside the VPC to the endpoint ENIs
- No transit gateway attachment by default; `enable_transit_gateway` adds one
- One VPC flow log to CloudWatch, on by default, `create_flow_log` turns it off

## Subnets are positional

The module places each subnet in `element(var.azs, index)` and uses one `azs` list for
every tier, so AZ assignment is positional and there is no per-tier AZ mapping. `subnets.tf`
derives `local.azs` from the subnet entries - the AZ of the first tier that has an entry at
each position - and the `subnet_layout` check fails the plan when an entry is not at the
position its own `az` implies.

In practice:

- Any number of entries in any AZs, in the order you want them.
- Several subnets in the same AZ is fine for the subnets; that AZ just appears twice in the
  derived order. The interface endpoints get one subnet per AZ, so they use the first entry in
  each AZ, see "Endpoints for ECS".
- A tier with fewer entries than another tier can only stop early, it cannot skip a
  position. So the public tier has to start at the same first AZ as the private tier:

```hcl
private_subnets = [
  { name = "app-2a", cidr = "10.2.1.0/24", az = "us-west-2a" },   # position 0
  { name = "app-2c", cidr = "10.2.3.0/24", az = "us-west-2c" },   # position 1
]
public_subnets = [
  { name = "edge-2a", cidr = "10.2.101.0/24", az = "us-west-2a" }, # position 0, ok
]
# A public subnet in us-west-2c alone would fail the check: position 0 is us-west-2a.
```

Names and CIDRs are checked for uniqueness and format. Terraform cannot test whether a
subnet CIDR lies inside `vpc_cidr`, so AWS is the one that rejects it, at apply.

`single_nat_gateway = false` is also how you get one route table per private subnet, which
is what you need when each VLAN wants its own gateway endpoint policy - the module sizes the
private route tables by the number of NAT gateways, and that count still applies when NAT is
off.

## Optional public tier

The public tier is a variable, not a separate file. With entries in `public_subnets` you get
a public route table and the internet gateway; `enable_nat_gateway` then becomes available,
because a NAT gateway has to sit in a public subnet.

| Variable | Purpose |
| --- | --- |
| `private_subnets` | The private VLANs, one object per subnet |
| `public_subnets` | Optional public VLANs, same shape, empty by default |
| `enable_nat_gateway` | Needs at least one public subnet |
| `single_nat_gateway` | One NAT for the tier, or one per private subnet (and one route table per subnet) |
| `one_nat_gateway_per_az` | Needs the public tier to be as long as the longest tier |
| `create_multiple_public_route_tables` | One public route table per subnet |
| `create_igw` | Skipped when the public tier is empty |

## Optional transit gateway attachment

Off by default, so the default plan is the isolated case. With `enable_transit_gateway = true`
you get a VPC attachment using the private subnets, association and propagation against the
pre-existing route table, and a `0.0.0.0/0` route on each private route table.

| Variable | Purpose |
| --- | --- |
| `enable_transit_gateway` | Turn the attachment on (default `false`) |
| `transit_gateway_id` | TGW ID or its ARN, required when the attachment is on |
| `transit_gateway_route_table_id` | TGW route table ID or its ARN, required when the attachment is on |
| `use_static_tgw_ids` | Skip the data source reads and use the values as given |
| `tgw_region` | TGW region when it differs from `aws_region` (reads only; an attachment cannot cross regions) |
| `transit_gateway_subnets` | Subnets the attachment uses, defaults to the private tier |
| `tgw_dns_support` | DNS resolution through the attachment, on by default |
| `replace_existing_association` | Drops the auto-association the TGW makes for a new attachment |
| `enable_tgw_association` / `enable_tgw_propagation` | On by default; propagation is usually the TGW owner's decision |
| `default_route_to_tgw` | `0.0.0.0/0` on each private route table |

The data sources read with the credentials Terraform is using, so a route table owned by
another account is never found: `DescribeTransitGatewayRouteTables` does not return tables
shared into this account, even after the RAM share is accepted. That is what produces

```
Error: No matching EC2 Transit Gateway Route Table found.
  with data.aws_ec2_transit_gateway_route_table.this
```

and `use_static_tgw_ids = true` is how you avoid it. IDs or ARNs both work, since an ARN is
reduced to the ID the resources take.

Two things this example checks rather than leaves to AWS:

- `default_route_to_tgw` and `enable_nat_gateway` cannot both be on. They would write the same
  `0.0.0.0/0` route onto the same private route tables, so pick one as the default path out.
  Gateway endpoints are not affected either way: their prefix-list route is more specific and
  wins over the TGW default route.
- The attachment needs two subnets in different AZs for resilience, so a private tier with one
  subnet has to be replaced with `transit_gateway_subnets`.

The route count follows the module's private route tables: one with `single_nat_gateway`, one per
AZ with `one_nat_gateway_per_az`, one per subnet position otherwise. That count also decides how
many endpoint policies apply, since one table per subnet is what lets each VLAN keep its own.

The route is written per route table, and the module associates every private subnet with one of
those tables, so `single_nat_gateway = false` is what gives several private subnets in the same AZ
a route each. With `single_nat_gateway = true` the tier shares one table and the single route covers
the whole tier. The count is recomputed from the module's formula rather than read from
`private_route_table_ids`, because those IDs only exist at apply time and a count or `for_each`
built from them cannot be planned.

The attachment is roughly `$0.05` per hour plus `$0.01` per GB processed through it, on top of
the endpoint costs. With the TGW as the default path, data to services outside this VPC goes
that way; traffic to the endpoint services stays on the endpoint because its route is more
specific.

## Endpoints for ECS

`endpoints.tf` turns each service name into an endpoint, using the `vpc-endpoints`
sub-module. Gateway services go on route tables, everything else is an interface endpoint
with an ENI in `endpoint_subnets` (the first private subnet in each AZ by default, since that
is where the tasks run).

| Service | Why ECS needs it |
| --- | --- |
| `ecr.api` | ECR API calls, e.g. `GetAuthorizationToken` |
| `ecr.dkr` | Image pull (`BatchGetImage`, layer download URLs) |
| `logs` | `awslogs` log driver. Required when the VPC has no internet gateway |
| `s3` (gateway) | ECR stores image layers in S3, so a pull needs it |
| `ecs`, `ecs-agent`, `ecs-telemetry` | Control plane and the container agent. Fargate does not need them; EC2 launch type and Service Connect do |

Add `secretsmanager`, `kms`, or `sqs` to the list when the task uses them; a task with no
internet path only reaches the services it has an endpoint for.

An interface endpoint takes one subnet per AZ, so `endpoint_subnets` cannot be the whole private
tier when a tier has two subnets in the same AZ: `CreateVpcEndpoint` fails at apply with
`DuplicateSubnetsInSameZone`. `endpoints.tf` defaults to the first subnet in each AZ instead,
which is enough for the whole AZ because a flow from any subnet in the VPC resolves to the
endpoint ENI:

```hcl
private_subnets = [
  { name = "app-2a", cidr = "10.2.1.0/24", az = "us-west-2a" },   # first in 2a, gets the ENIs
  { name = "web-2a", cidr = "10.2.4.0/24", az = "us-west-2a" },   # second in 2a, no ENI
  { name = "app-2b", cidr = "10.2.2.0/24", az = "us-west-2b" },
]
# endpoint_subnets is app-2a and app-2b; tasks in web-2a still reach every endpoint.
```

Two things to know:

- Service names are resolved by the `aws_vpc_endpoint_service` data source at plan time, so a
  name your region does not offer fails the plan. Older regions may use `ecs.agent` or
  `ecs.data` instead of `ecs-agent`. Remove what your region does not have.
- `endpoint_private_dns_enabled = true` is what makes the service DNS names resolve to the
  endpoint. The ECS agent follows `ecs-a.<region>.amazonaws.com` and
  `ecs-t.<region>.amazonaws.com`, so private DNS and `enable_dns_support` both have to stay
  on. In a private-only VPC, DNS still works because resolution happens inside the VPC; there
  is no internet path, and none is needed.
- A list given to `endpoint_subnets` is used as it is, because Terraform cannot tell which AZ a
  subnet ID is in at plan time. The check reports a list with more entries than this VPC has
  distinct AZs; two entries in the same AZ there is still only found at apply.

Cost: interface endpoints are about `$0.01` per hour per endpoint ENI plus `$0.01` per GB
processed, and an endpoint has one ENI per AZ it is given a subnet in. The default six interface
endpoints across three AZs is roughly 18 ENIs, about `$130` a month, which is still less than a
NAT gateway once tasks pull images. A private tier with two subnets in the same AZ costs the
same as the one-per-AZ default, because the second subnet in that AZ gets no ENI. Gateway
endpoints are free. If you leave `enable_endpoints` false and enable NAT instead, you pay the
NAT hourly plus processing and the endpoints go away.

## VPC flow log

One flow log for the whole VPC, on by default, writing to CloudWatch with a 90-day retention and
a role created here. That is the coarse option: a record names the interface the flow was seen on,
so which VLAN it belonged to is worked out afterwards. Per-VLAN logging would mean one flow log
per subnet with `subnet_id`, which is a different resource per VLAN.

| Variable | Purpose |
| --- | --- |
| `create_flow_log` | Turn it on or off (default `true`) |
| `flow_log_destination_type` | `cloud-watch-logs`, `s3`, or `kinesis-data-firehose` |
| `flow_log_destination` | Existing log group, bucket, or delivery stream ARN |
| `flow_log_traffic_type` | `ACCEPT`, `REJECT`, or `ALL` |
| `flow_log_max_aggregation_interval` | 60 or 600 seconds |
| `flow_log_retention_in_days` | Retention of the log group created here |
| `create_flow_log_log_group` | Create the group, or deliver to an existing one |
| `create_flow_log_iam_role` / `flow_log_iam_role_arn` | Role created here, or an existing one |

Two things worth knowing:

- `REJECT` is the interesting traffic type in a private-only VPC: it records a task trying to
  reach a service it has no endpoint for, which is the failure mode this example is built around.
  `ALL` is the default because it keeps the accepted records next to them.
- Traffic that stays inside the VPC is recorded as well, so a busy VPC writes a lot. CloudWatch
  Logs charges roughly `$0.50` per GB ingested plus storage, and S3 is the cheaper place to keep
  records for long. A TGW-scoped flow log is a separate resource, on the attachment rather than
  the VPC, and needs the transit gateway to have logging enabled, so this example does not do it.

The check block wants a destination, and for CloudWatch or Firehose a role
`vpc-flow-logs.amazonaws.com` can assume. An S3 destination needs no role, so
`create_flow_log_iam_role` is ignored there.

## Running it

```bash
cd examples/vpc-subnets-by-az
cp example.auto.tfvars.example example.auto.tfvars   # optional; the defaults are the private-only case
terraform init
terraform plan
terraform apply
```

The checks in `subnets.tf` and `endpoints.tf` run at plan time, so a bad AZ order, an
`endpoint_subnets` list longer than the number of distinct AZs, or a NAT gateway with no public
subnet is reported before anything is created.

## Things to watch

- Interface endpoints take one subnet per AZ, so only the first subnet in an AZ holds the ENIs.
  The zonal DNS name for that AZ points at that ENI, and tasks in the other subnets of the AZ
  reach it through the VPC's local route.
- Interface endpoints cannot be created in subnets shared with you, only used from them.
- With the attachment on, the TGW route table still needs a route back to `10.2.0.0/16`,
  otherwise traffic leaves the VPC and never comes back. If the network team owns that route,
  set `enable_tgw_propagation = false` and ask for a static route.
- The share has to be accepted in this account before the association works, automatically
  inside an AWS Organization and otherwise in the RAM console. Terraform cannot create it.
- ECR pull-through cache rules need a NAT gateway for the first pull, so an isolated VPC with
  no public subnet cannot use them.
- Windows images with foreign layers are fetched from Microsoft unless the image was pushed
  with `--allow-nondistributable-artifacts`.
- Endpoint policies are not set here; without one an endpoint allows full access to the
  service. Add a policy per endpoint when the tasks only need specific actions, and restrict
  the task execution role to the VPC or endpoint with condition keys.
