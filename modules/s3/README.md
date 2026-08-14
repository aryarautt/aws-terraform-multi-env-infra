# Module: `s3`

**Locked-down object storage**

Creates an S3 bucket with all public access blocked, ACLs disabled, encryption at rest, versioning, lifecycle rules, and a bucket policy denying non-TLS requests and unencrypted uploads.

## Usage

```hcl
module "s3" {
  source = "../../modules/s3"

  name_prefix = local.name_prefix
  # ... see variables below
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `bucket_name` | `string` | **yes** | Bucket name. Must be globally unique across ALL AWS accounts - include the account ID and region to guarantee that. |
| `force_destroy` | `bool` | no | Allow terraform destroy to delete a bucket that still contains objects. True in dev for clean teardown; false in production so a destroy fails loudly rather than deleting data. |
| `enable_versioning` | `bool` | no | Keep every version of every object. Protects against accidental deletion and ransomware. |
| `enable_lifecycle_rules` | `bool` | no | Expire old object versions and clean up incomplete multipart uploads. Strongly recommended whenever versioning is on, or storage grows without limit. |
| `noncurrent_version_expiration_days` | `number` | no | Days to retain non-current object versions before permanent deletion. |
| `transition_to_ia_days` | `number` | no | Days before objects move to Standard-Infrequent Access, which is cheaper to store but costs more to retrieve. 0 disables the transition. |
| `kms_key_arn` | `string` | no | Customer-managed KMS key ARN. Null uses free SSE-S3 (AES256) encryption instead. |
| `enable_alb_access_logs` | `bool` | no | Add a bucket policy statement permitting the ALB log delivery service to write access logs under the alb/ prefix. |
| `tags` | `map(string)` | no | Tags applied to every resource this module creates. |

## Outputs

| Name | Description |
|------|-------------|
| `bucket_id` | Name of the bucket. |
| `bucket_arn` | ARN of the bucket. Passed to the iam module so the EC2 role gets access to this bucket only. |
| `bucket_domain_name` | Domain name of the bucket. |
| `bucket_regional_domain_name` | Region-specific domain name of the bucket. |

## Notes

Requires Terraform `>= 1.10.0` and AWS provider `>= 5.70, < 7.0` (see `versions.tf`).
