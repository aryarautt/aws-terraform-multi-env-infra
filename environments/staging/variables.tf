###############################################################################
# Environment input variables.
#
# This file is IDENTICAL in dev, staging and production. Only the VALUES,
# in terraform.tfvars, differ. That is what keeps the environments
# structurally consistent while allowing them to be sized differently.
###############################################################################

# ---- Identity ---------------------------------------------------------------

variable "project_name" {
  description = "Project name. Prefixes every resource name."
  type        = string
  default     = "aws-tf-infra"
}

variable "environment" {
  description = "Environment name. Must match the directory name and the state key."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile. Null uses the default credential chain, which is what CI/CD uses via OIDC."
  type        = string
  default     = null
}

variable "owner" {
  description = "Team or person responsible. Appears in tags and is how you find who to contact about an unexpected resource."
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Cost allocation tag, used to break down the bill by environment in Cost Explorer."
  type        = string
  default     = "engineering"
}

variable "repository_url" {
  description = "Repository URL, tagged onto resources so anyone in the console can find the code that created them."
  type        = string
  default     = "https://github.com/aryarautt/aws-terraform-multi-env-infra"
}

# ---- Network ----------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR block. Each environment uses a DIFFERENT range so they could be peered later without conflicts."
  type        = string
}

variable "az_count" {
  description = "Availability Zones to span. Minimum 2 for ALB and RDS."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "COST LEVER: NAT Gateway is ~$40/month and not in any free tier. False in dev."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT Gateway across AZs. Cheaper but a single point of failure. False in production."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Capture VPC Flow Logs. Billed per GB ingested."
  type        = bool
  default     = false
}

# ---- Application ------------------------------------------------------------

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB health check path. Must be lightweight and must not query the database."
  type        = string
  default     = "/health"
}

variable "instance_type" {
  description = "COST LEVER: EC2 instance size."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 20
}

variable "asg_min_size" {
  description = "Minimum instances."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "COST LEVER: instances running under normal conditions."
  type        = number
  default     = 1
}

variable "enable_autoscaling" {
  description = "Attach a CPU target-tracking scaling policy."
  type        = bool
  default     = false
}

variable "target_cpu_utilization" {
  description = "Average CPU the scaling policy targets."
  type        = number
  default     = 60
}

variable "enable_detailed_monitoring" {
  description = "1-minute EC2 metrics instead of 5-minute. Billed per instance."
  type        = bool
  default     = false
}

# ---- Load balancer ----------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, HTTPS is enabled and HTTP redirects to it. Requires a domain you control."
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "Block terraform destroy from deleting the load balancer. Production only."
  type        = bool
  default     = false
}

variable "enable_alb_access_logs" {
  description = "Write ALB access logs to the application S3 bucket."
  type        = bool
  default     = false
}

# ---- Database ---------------------------------------------------------------

variable "enable_rds" {
  description = "COST LEVER: create the database. False skips RDS entirely, saving ~$13/month plus storage."
  type        = bool
  default     = true
}

variable "db_engine" {
  description = "Database engine."
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "Engine major version."
  type        = string
  default     = "16"
}

variable "db_parameter_group_family" {
  description = "Parameter group family. Must match the engine version."
  type        = string
  default     = "postgres16"
}

variable "db_instance_class" {
  description = "COST LEVER: database instance size."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage in GB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB."
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "appdb"
}

variable "db_port" {
  description = "Database port. 5432 PostgreSQL, 3306 MySQL."
  type        = number
  default     = 5432
}

variable "db_multi_az" {
  description = "COST LEVER: synchronous standby in a second AZ. DOUBLES the database cost. Production only."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Days of automated backups. 0 disables point-in-time recovery entirely - never 0 in production."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Block deletion of the database. Must be disabled and applied before a genuine teardown."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on deletion. True in dev - snapshots persist and keep billing after everything else is destroyed."
  type        = bool
  default     = true
}

variable "db_final_snapshot_suffix" {
  description = "Suffix making the final snapshot name unique. Reusing an existing name causes destroy to fail."
  type        = string
  default     = "v1"
}

variable "db_performance_insights" {
  description = "Enable Performance Insights. Free at 7-day retention."
  type        = bool
  default     = false
}

variable "db_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds. 0 disables it."
  type        = number
  default     = 0
}

# ---- Storage ----------------------------------------------------------------

variable "s3_force_destroy" {
  description = "Allow destroy of a bucket containing objects. True in dev for clean teardown, false in production."
  type        = bool
  default     = false
}

variable "s3_enable_versioning" {
  description = "Keep every version of every object."
  type        = bool
  default     = true
}

variable "s3_noncurrent_version_days" {
  description = "Days to retain non-current object versions."
  type        = number
  default     = 30
}

# ---- Monitoring -------------------------------------------------------------

variable "log_retention_days" {
  description = "COST LEVER: days to retain logs. Longer retention costs more storage."
  type        = number
  default     = 7
}

variable "cpu_alarm_threshold" {
  description = "CPU percentage that triggers a high-CPU alarm."
  type        = number
  default     = 80
}

variable "alarm_email" {
  description = "Email subscribed to alarm notifications. AWS sends a confirmation link that must be clicked."
  type        = string
  default     = null
}

variable "create_dashboard" {
  description = "Create a CloudWatch dashboard. First three per account are free."
  type        = bool
  default     = true
}

# ---- Security ---------------------------------------------------------------

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary capping what the EC2 role can ever be granted."
  type        = string
  default     = null
}
