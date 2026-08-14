# Module: `vpc`

**Multi-AZ network foundation**

Creates the VPC, three tiers of subnets (public, private-app, private-db) across N Availability Zones, Internet Gateway, optional NAT Gateway(s), route tables, a free S3 Gateway Endpoint, optional VPC Flow Logs, and locks down the default Security Group.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names, e.g. 'myapp-dev'. |
| `aws_region` | `string` | **yes** | AWS region. Passed in explicitly rather than read from a data source so the module stays portable and version-safe. |
| `vpc_cidr` | `string` | no | CIDR block for the VPC. A /16 gives 65,536 addresses - plenty of room to grow, and small enough to avoid overlapping with other networks you may peer with later. |
| `subnet_newbits` | `number` | no | Bits to add to the VPC prefix when carving subnets. 8 on a /16 produces /24 subnets (251 usable IPs each - AWS reserves 5). |
| `az_count` | `number` | no | Number of Availability Zones to span. Minimum 2 - both the Application Load Balancer and RDS subnet groups require at least two AZs. |
| `enable_nat_gateway` | `bool` | no | Create NAT Gateway(s) so private subnets can reach the internet outbound. COSTS ~$40/month each. Set false in dev; the S3 Gateway Endpoint still provides free S3 access. |
| `single_nat_gateway` | `bool` | no | Share one NAT Gateway across all AZs instead of one per AZ. Cheaper, but it becomes a single point of failure - if its AZ goes down, every private subnet loses outbound internet. Acceptable in dev/staging, not in production. |
| `enable_s3_endpoint` | `bool` | no | Create a Gateway VPC Endpoint for S3. Free, keeps S3 traffic off the public internet, and removes the need for a NAT Gateway just to reach S3. |
| `enable_flow_logs` | `bool` | no | Capture VPC Flow Logs to CloudWatch. Invaluable for security auditing and for debugging connectivity, but log ingestion is billed per GB. |
| `flow_logs_retention_days` | `number` | no | How long to keep VPC Flow Logs. Longer retention costs more storage. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC. |
| `vpc_cidr_block` | CIDR block of the VPC. Used by Security Groups that need to allow VPC-internal traffic. |
| `public_subnet_ids` | IDs of the public subnets. The ALB is placed here. |
| `private_app_subnet_ids` | IDs of the private application subnets. EC2 instances are placed here. |
| `private_db_subnet_ids` | IDs of the private database subnets. The RDS subnet group uses these. |
| `availability_zones` | The Availability Zones this VPC spans. |
| `internet_gateway_id` | ID of the Internet Gateway. |
| `nat_gateway_ids` | IDs of the NAT Gateways. Empty when enable_nat_gateway is false. |
| `nat_gateway_public_ips` | Public IPs of the NAT Gateways. These are the addresses external services will see as the origin of outbound traffic - useful when a third-party API requires IP allow-listing. |
| `public_route_table_id` | ID of the public route table. |
| `private_app_route_table_ids` | IDs of the private application route tables. |
| `private_db_route_table_id` | ID of the private database route table. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
