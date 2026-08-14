variable "bucket_name" {
  description = "Bucket name. Must be globally unique across ALL AWS accounts - include the account ID and region to guarantee that."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names must be 3-63 characters, lowercase letters, numbers, hyphens and dots only, starting and ending alphanumeric."
  }
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a bucket that still contains objects. True in dev for clean teardown; false in production so a destroy fails loudly rather than deleting data."
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Keep every version of every object. Protects against accidental deletion and ransomware."
  type        = bool
  default     = true
}

variable "enable_lifecycle_rules" {
  description = "Expire old object versions and clean up incomplete multipart uploads. Strongly recommended whenever versioning is on, or storage grows without limit."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain non-current object versions before permanent deletion."
  type        = number
  default     = 30
}

variable "transition_to_ia_days" {
  description = "Days before objects move to Standard-Infrequent Access, which is cheaper to store but costs more to retrieve. 0 disables the transition."
  type        = number
  default     = 0
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN. Null uses free SSE-S3 (AES256) encryption instead."
  type        = string
  default     = null
}

variable "enable_alb_access_logs" {
  description = "Add a bucket policy statement permitting the ALB log delivery service to write access logs under the alb/ prefix."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
