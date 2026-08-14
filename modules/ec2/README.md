# Module: `ec2`

**Application tier as Launch Template + ASG**

Creates a Launch Template (IMDSv2 enforced, encrypted EBS, cloud-init bootstrap) and an Auto Scaling Group that places instances in private subnets, registers them with the ALB target group, and replaces unhealthy ones automatically.

## Usage

```hcl
module "ec2" {
  source = "../../modules/ec2"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names, e.g. 'myapp-dev'. |
| `project_name` | `string` | **yes** | Project name, displayed on the application page. |
| `environment` | `string` | **yes** | Environment name (dev, staging, production). |
| `aws_region` | `string` | **yes** | AWS region, passed to the CloudWatch agent configuration. |
| `private_subnet_ids` | `list(string)` | **yes** | Private application subnet IDs the Auto Scaling Group launches into. Never public subnets. |
| `security_group_id` | `string` | **yes** | Security Group applied to the instances. |
| `instance_profile_name` | `string` | **yes** | IAM instance profile name, from the iam module. |
| `target_group_arns` | `list(string)` | no | ALB target group ARNs to register instances with. Empty list means no load balancer. |
| `log_group_name` | `string` | **yes** | CloudWatch Log Group the instances ship logs to. |
| `ami_id` | `string` | no | Explicit AMI ID. Null uses the latest Amazon Linux 2023 image. Pin this in production so a new AMI release cannot trigger an unplanned instance refresh. |
| `instance_type` | `string` | no | EC2 instance type. This is a primary cost lever between environments. |
| `root_volume_size` | `number` | no | Root EBS volume size in GB. |
| `app_port` | `number` | no | Port the application listens on. |
| `min_size` | `number` | no | Minimum instances in the Auto Scaling Group. |
| `max_size` | `number` | no | Maximum instances in the Auto Scaling Group. |
| `desired_capacity` | `number` | no | Instances to run under normal conditions. |
| `health_check_grace_period` | `number` | no | Seconds to wait after launch before health checks count. Must exceed boot plus application start time, or the ASG kills instances while they are still starting - a classic infinite-replacement loop. |
| `instance_refresh_min_healthy_percentage` | `number` | no | Percentage of capacity to keep in service during a rolling instance refresh. |
| `enable_detailed_monitoring` | `bool` | no | 1-minute CloudWatch metrics instead of 5-minute. Billed per instance. |
| `enable_autoscaling` | `bool` | no | Attach a CPU target-tracking scaling policy. |
| `target_cpu_utilization` | `number` | no | Average CPU percentage the scaling policy aims to hold. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `autoscaling_group_name` | Name of the Auto Scaling Group. |
| `autoscaling_group_arn` | ARN of the Auto Scaling Group. |
| `launch_template_id` | ID of the Launch Template. |
| `launch_template_latest_version` | Latest version number of the Launch Template. |
| `ami_id` | AMI ID the instances were launched from. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
