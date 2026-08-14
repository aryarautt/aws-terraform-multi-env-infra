# Module: `cloudwatch`

**Logs, alarms and dashboard**

Creates the application log group with explicit retention, an SNS topic for notifications, metric alarms across EC2/ALB/RDS, and a single-page dashboard.

## Usage

```hcl
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names, e.g. 'myapp-dev'. |
| `aws_region` | `string` | **yes** | AWS region, used in dashboard widget definitions. |
| `log_group_name` | `string` | **yes** | Name of the application log group. Defined in the environment's locals and passed to both this module and the ec2 module, to avoid a dependency cycle. |
| `log_retention_days` | `number` | no | Days to retain application logs. 0 means never expire, which accumulates storage cost indefinitely - avoid it. |
| `kms_key_arn` | `string` | no | KMS key ARN for encrypting log data at rest. Null uses CloudWatch's default encryption. |
| `create_sns_topic` | `bool` | no | Create an SNS topic for alarm notifications. |
| `sns_topic_arn` | `string` | no | Existing SNS topic ARN to send alarms to. Takes precedence over create_sns_topic. |
| `alarm_email` | `string` | no | Email address subscribed to the alarm topic. AWS sends a confirmation link that must be clicked before alarms are delivered. |
| `autoscaling_group_name` | `string` | no | Auto Scaling Group name to monitor. Null skips all EC2 alarms. |
| `alb_arn_suffix` | `string` | no | ALB ARN suffix (the part CloudWatch uses as a dimension). Null skips all load balancer alarms. |
| `target_group_arn_suffix` | `string` | no | Target group ARN suffix. Required for the unhealthy-host alarm. |
| `db_instance_id` | `string` | no | RDS instance identifier to monitor. Null skips all database alarms. |
| `cpu_alarm_threshold` | `number` | no | CPU percentage that triggers a high-CPU alarm. |
| `alb_5xx_threshold` | `number` | no | Number of ELB 5xx responses in a 5-minute window before alarming. |
| `response_time_threshold` | `number` | no | p95 target response time in seconds before alarming. |
| `rds_free_storage_threshold_gb` | `number` | no | Free database storage in GB below which an alarm fires. |
| `rds_connection_threshold` | `number` | no | Database connection count above which an alarm fires. Size this to the instance class - a db.t4g.micro supports far fewer connections than a db.r6g.large. |
| `create_dashboard` | `bool` | no | Create a CloudWatch dashboard. Free for the first three dashboards per account. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `log_group_name` | Name of the application log group. Passed to the ec2 module so the CloudWatch agent knows where to ship logs. |
| `log_group_arn` | ARN of the application log group. |
| `sns_topic_arn` | ARN of the alarm notification topic. |
| `dashboard_name` | Name of the CloudWatch dashboard. |
| `alarm_names` | Names of every alarm created, for verification and evidence capture. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
