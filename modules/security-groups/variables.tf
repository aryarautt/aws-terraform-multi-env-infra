variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. 'myapp-dev'."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC these Security Groups belong to. Supplied by the vpc module's output."
  type        = string
}

variable "app_port" {
  description = "TCP port the application listens on. The ALB forwards to this port and it is the only port the app tier accepts."
  type        = number
  default     = 80
}

variable "db_port" {
  description = "TCP port the database listens on. 5432 for PostgreSQL, 3306 for MySQL/MariaDB."
  type        = number
  default     = 5432
}

variable "enable_https" {
  description = "Open port 443 on the load balancer. Requires an ACM certificate on the ALB listener."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
