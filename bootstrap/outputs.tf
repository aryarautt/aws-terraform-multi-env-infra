output "state_bucket_name" {
  description = "Name of the Terraform state bucket. Copy this into each environment's backend.tf."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "state_bucket_region" {
  description = "Region the state bucket lives in."
  value       = var.aws_region
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role. Set this as the AWS_ROLE_ARN repository variable in GitHub."
  value       = try(aws_iam_role.github_actions[0].arn, null)
}

output "account_id" {
  description = "AWS account ID this bootstrap ran against."
  value       = data.aws_caller_identity.current.account_id
}

output "backend_configuration" {
  description = "Ready-to-paste backend block for each environment."
  value       = <<-EOT

    Add this to environments/<env>/backend.tf, changing only the key:

    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.state.id}"
        key          = "<env>/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true
      }
    }

  EOT
}
