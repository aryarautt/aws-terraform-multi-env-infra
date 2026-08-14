variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. 'myapp-dev'."
  type        = string
}

variable "project_name" {
  description = "Project name, displayed on the application page."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, production)."
  type        = string
}

variable "aws_region" {
  description = "AWS region, passed to the CloudWatch agent configuration."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private application subnet IDs the Auto Scaling Group launches into. Never public subnets."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security Group applied to the instances."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile name, from the iam module."
  type        = string
}

variable "target_group_arns" {
  description = "ALB target group ARNs to register instances with. Empty list means no load balancer."
  type        = list(string)
  default     = []
}

variable "log_group_name" {
  description = "CloudWatch Log Group the instances ship logs to."
  type        = string
}

variable "ami_id" {
  description = "Explicit AMI ID. Null uses the latest Amazon Linux 2023 image. Pin this in production so a new AMI release cannot trigger an unplanned instance refresh."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type. This is a primary cost lever between environments."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20
}

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 80
}

variable "min_size" {
  description = "Minimum instances in the Auto Scaling Group."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum instances in the Auto Scaling Group."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Instances to run under normal conditions."
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "Seconds to wait after launch before health checks count. Must exceed boot plus application start time, or the ASG kills instances while they are still starting - a classic infinite-replacement loop."
  type        = number
  default     = 300
}

variable "instance_refresh_min_healthy_percentage" {
  description = "Percentage of capacity to keep in service during a rolling instance refresh."
  type        = number
  default     = 50
}

variable "enable_detailed_monitoring" {
  description = "1-minute CloudWatch metrics instead of 5-minute. Billed per instance."
  type        = bool
  default     = false
}

variable "enable_autoscaling" {
  description = "Attach a CPU target-tracking scaling policy."
  type        = bool
  default     = false
}

variable "target_cpu_utilization" {
  description = "Average CPU percentage the scaling policy aims to hold."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
