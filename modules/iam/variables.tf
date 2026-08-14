variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. 'myapp-dev'."
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the application S3 bucket the instances may access. Null disables the S3 policy entirely."
  type        = string
  default     = null
}

variable "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding database credentials. Null disables the secrets policy."
  type        = string
  default     = null
}

variable "db_secret_kms_key_arn" {
  description = "ARN of the KMS key encrypting the database secret. Required to decrypt RDS-managed secrets."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary that caps the maximum permissions this role can ever hold, regardless of attached policies."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
