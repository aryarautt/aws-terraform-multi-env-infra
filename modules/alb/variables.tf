variable "name_prefix" {
  description = "Prefix applied to all resource names. Note: ALB and target group names are capped at 32 characters, so this module uses name_prefix with substr()."
  type        = string
}

variable "vpc_id" {
  description = "VPC the target group belongs to."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the load balancer nodes. Minimum two, in different AZs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An Application Load Balancer requires at least two subnets in different Availability Zones."
  }
}

variable "security_group_id" {
  description = "Security Group for the load balancer."
  type        = string
}

variable "app_port" {
  description = "Port on the targets that the ALB forwards to."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Path the ALB polls to decide target health. Should be lightweight and must not query the database."
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between health checks."
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a health check response. Must be less than health_check_interval."
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Consecutive successful checks before a target receives traffic."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failed checks before a target is removed from service."
  type        = number
  default     = 3
}

variable "deregistration_delay" {
  description = "Seconds to allow in-flight requests to complete before removing a target."
  type        = number
  default     = 60
}

variable "idle_timeout" {
  description = "Seconds an idle connection is held open. Must exceed the backend keep-alive timeout to avoid intermittent 502s."
  type        = number
  default     = 60
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, an HTTPS listener is created and HTTP is redirected to it. Requires a domain you control."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS negotiation policy. The default enforces TLS 1.2 as a minimum."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "enable_deletion_protection" {
  description = "Block terraform destroy from deleting the load balancer. On in production only."
  type        = bool
  default     = false
}

variable "enable_stickiness" {
  description = "Bind a client to one target with a cookie. Only for applications holding server-side session state."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs. Null disables access logging."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
