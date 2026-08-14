variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. 'myapp-dev'."
  type        = string
}

variable "aws_region" {
  description = "AWS region, used in dashboard widget definitions."
  type        = string
}

variable "log_group_name" {
  description = "Name of the application log group. Defined in the environment's locals and passed to both this module and the ec2 module, to avoid a dependency cycle."
  type        = string
}

variable "log_retention_days" {
  description = "Days to retain application logs. 0 means never expire, which accumulates storage cost indefinitely - avoid it."
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be one of the values CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting log data at rest. Null uses CloudWatch's default encryption."
  type        = string
  default     = null
}

variable "create_sns_topic" {
  description = "Create an SNS topic for alarm notifications."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "Existing SNS topic ARN to send alarms to. Takes precedence over create_sns_topic."
  type        = string
  default     = null
}

variable "alarm_email" {
  description = "Email address subscribed to the alarm topic. AWS sends a confirmation link that must be clicked before alarms are delivered."
  type        = string
  default     = null
}

variable "autoscaling_group_name" {
  description = "Auto Scaling Group name to monitor. Null skips all EC2 alarms."
  type        = string
  default     = null
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (the part CloudWatch uses as a dimension). Null skips all load balancer alarms."
  type        = string
  default     = null
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix. Required for the unhealthy-host alarm."
  type        = string
  default     = null
}

variable "db_instance_id" {
  description = "RDS instance identifier to monitor. Null skips all database alarms."
  type        = string
  default     = null
}

variable "cpu_alarm_threshold" {
  description = "CPU percentage that triggers a high-CPU alarm."
  type        = number
  default     = 80
}

variable "alb_5xx_threshold" {
  description = "Number of ELB 5xx responses in a 5-minute window before alarming."
  type        = number
  default     = 10
}

variable "response_time_threshold" {
  description = "p95 target response time in seconds before alarming."
  type        = number
  default     = 2
}

variable "rds_free_storage_threshold_gb" {
  description = "Free database storage in GB below which an alarm fires."
  type        = number
  default     = 5
}

variable "rds_connection_threshold" {
  description = "Database connection count above which an alarm fires. Size this to the instance class - a db.t4g.micro supports far fewer connections than a db.r6g.large."
  type        = number
  default     = 50
}

variable "create_dashboard" {
  description = "Create a CloudWatch dashboard. Free for the first three dashboards per account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
