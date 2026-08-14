# Module: `iam`

**Least-privilege EC2 instance role**

Creates the IAM role and instance profile assumed by application instances: SSM Session Manager, CloudWatch agent, scoped S3 access and scoped Secrets Manager access. No access keys are ever created.

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name_prefix` | `string` | **yes** | Prefix applied to all resource names, e.g. 'myapp-dev'. |
| `s3_bucket_arn` | `string` | no | ARN of the application S3 bucket the instances may access. Null disables the S3 policy entirely. |
| `db_secret_arn` | `string` | no | ARN of the Secrets Manager secret holding database credentials. Null disables the secrets policy. |
| `db_secret_kms_key_arn` | `string` | no | ARN of the KMS key encrypting the database secret. Required to decrypt RDS-managed secrets. |
| `permissions_boundary_arn` | `string` | no | Optional permissions boundary that caps the maximum permissions this role can ever hold, regardless of attached policies. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `ec2_role_arn` | ARN of the EC2 instance role. |
| `ec2_role_name` | Name of the EC2 instance role. |
| `ec2_instance_profile_name` | Name of the instance profile to attach to the launch template. |
| `ec2_instance_profile_arn` | ARN of the instance profile. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
