# Module: `alb`

**Public entry point**

Creates the internet-facing Application Load Balancer, target group with health checks, and HTTP/HTTPS listeners. When an ACM certificate is supplied, HTTP is 301-redirected to HTTPS.

## Usage

```hcl
module "alb" {
  source = "../../modules/alb"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names. Note: ALB and target group names are capped at 32 characters, so this module uses name_prefix with substr(). |
| `vpc_id` | `string` | **yes** | VPC the target group belongs to. |
| `public_subnet_ids` | `list(string)` | **yes** | Public subnet IDs for the load balancer nodes. Minimum two, in different AZs. |
| `security_group_id` | `string` | **yes** | Security Group for the load balancer. |
| `app_port` | `number` | no | Port on the targets that the ALB forwards to. |
| `health_check_path` | `string` | no | Path the ALB polls to decide target health. Should be lightweight and must not query the database. |
| `health_check_interval` | `number` | no | Seconds between health checks. |
| `health_check_timeout` | `number` | no | Seconds to wait for a health check response. Must be less than health_check_interval. |
| `healthy_threshold` | `number` | no | Consecutive successful checks before a target receives traffic. |
| `unhealthy_threshold` | `number` | no | Consecutive failed checks before a target is removed from service. |
| `deregistration_delay` | `number` | no | Seconds to allow in-flight requests to complete before removing a target. |
| `idle_timeout` | `number` | no | Seconds an idle connection is held open. Must exceed the backend keep-alive timeout to avoid intermittent 502s. |
| `certificate_arn` | `string` | no | ACM certificate ARN. When set, an HTTPS listener is created and HTTP is redirected to it. Requires a domain you control. |
| `ssl_policy` | `string` | no | TLS negotiation policy. The default enforces TLS 1.2 as a minimum. |
| `enable_deletion_protection` | `bool` | no | Block terraform destroy from deleting the load balancer. On in production only. |
| `enable_stickiness` | `bool` | no | Bind a client to one target with a cookie. Only for applications holding server-side session state. |
| `access_logs_bucket` | `string` | no | S3 bucket for ALB access logs. Null disables access logging. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `alb_arn` | ARN of the Application Load Balancer. |
| `alb_dns_name` | Public DNS name of the load balancer. This is the URL users hit. Point a CNAME or Route 53 alias at it for a real domain. |
| `alb_zone_id` | Route 53 hosted zone ID of the load balancer, required when creating an alias record. |
| `alb_url` | Ready-to-use URL for the application. |
| `target_group_arn` | ARN of the target group. Passed to the ec2 module so the Auto Scaling Group registers instances with it. |
| `target_group_name` | Name of the target group. |
| `http_listener_arn` | ARN of the HTTP listener. |
| `https_listener_arn` | ARN of the HTTPS listener, when a certificate was supplied. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
