# Module: `security-groups`

**Layered, self-referencing firewall rules**

Creates the ALB, application and database Security Groups. Rules reference other Security Groups rather than CIDR ranges, so they remain correct as instances are replaced or scaled.

## Usage

```hcl
module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names, e.g. 'myapp-dev'. |
| `vpc_id` | `string` | **yes** | ID of the VPC these Security Groups belong to. Supplied by the vpc module's output. |
| `app_port` | `number` | no | TCP port the application listens on. The ALB forwards to this port and it is the only port the app tier accepts. |
| `db_port` | `number` | no | TCP port the database listens on. 5432 for PostgreSQL, 3306 for MySQL/MariaDB. |
| `enable_https` | `bool` | no | Open port 443 on the load balancer. Requires an ACM certificate on the ALB listener. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `alb_security_group_id` | Security Group for the Application Load Balancer. |
| `app_security_group_id` | Security Group for the EC2 application instances. |
| `db_security_group_id` | Security Group for the RDS database instance. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
