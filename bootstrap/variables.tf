variable "project_name" {
  description = "Project name, used as a prefix for the state bucket and IAM roles."
  type        = string
  default     = "aws-tf-infra"
}

variable "aws_region" {
  description = "Region the state bucket is created in. All environments use this same bucket regardless of which region they deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile to authenticate with. Null uses the default credential chain (useful in CI)."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "Explicit state bucket name. Null generates one as <project>-tfstate-<account-id>-<region>."
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for state encryption. Null uses free SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "state_version_retention_days" {
  description = "Days to retain non-current state file versions before expiry. This is your state recovery window."
  type        = number
  default     = 90
}

variable "enable_github_oidc" {
  description = "Create the GitHub Actions OIDC provider and CI/CD role. Set false if you are not using GitHub Actions."
  type        = bool
  default     = true
}

variable "github_allowed_subjects" {
  description = <<-EOT
    Which GitHub repositories and refs may assume the CI/CD role.

    MUST be scoped to your own repository. A wildcard here would let any
    repository on GitHub assume the role.

    Examples:
      ["repo:my-user/my-repo:ref:refs/heads/main"]      only the main branch
      ["repo:my-user/my-repo:pull_request"]             only pull requests
      ["repo:my-user/my-repo:environment:production"]   only that environment
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for s in var.github_allowed_subjects : startswith(s, "repo:")
    ])
    error_message = "Every subject must start with 'repo:' and name a specific repository. A bare wildcard would allow any GitHub repository to assume this role."
  }
}

variable "github_actions_policy_arn" {
  description = "Managed policy attached to the CI/CD role. PowerUserAccess excludes IAM writes, which prevents privilege escalation. Replace with a scoped custom policy for production."
  type        = string
  default     = "arn:aws:iam::aws:policy/PowerUserAccess"
}
