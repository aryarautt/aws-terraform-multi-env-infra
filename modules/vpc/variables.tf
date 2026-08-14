variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. 'myapp-dev'."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters, numbers and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region. Passed in explicitly rather than read from a data source so the module stays portable and version-safe."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. A /16 gives 65,536 addresses - plenty of room to grow, and small enough to avoid overlapping with other networks you may peer with later."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "subnet_newbits" {
  description = "Bits to add to the VPC prefix when carving subnets. 8 on a /16 produces /24 subnets (251 usable IPs each - AWS reserves 5)."
  type        = number
  default     = 8
}

variable "az_count" {
  description = "Number of Availability Zones to span. Minimum 2 - both the Application Load Balancer and RDS subnet groups require at least two AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4. ALB and RDS both require a minimum of 2."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) so private subnets can reach the internet outbound. COSTS ~$40/month each. Set false in dev; the S3 Gateway Endpoint still provides free S3 access."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Share one NAT Gateway across all AZs instead of one per AZ. Cheaper, but it becomes a single point of failure - if its AZ goes down, every private subnet loses outbound internet. Acceptable in dev/staging, not in production."
  type        = bool
  default     = false
}

variable "enable_s3_endpoint" {
  description = "Create a Gateway VPC Endpoint for S3. Free, keeps S3 traffic off the public internet, and removes the need for a NAT Gateway just to reach S3."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Capture VPC Flow Logs to CloudWatch. Invaluable for security auditing and for debugging connectivity, but log ingestion is billed per GB."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "How long to keep VPC Flow Logs. Longer retention costs more storage."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
