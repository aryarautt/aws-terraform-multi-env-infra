# Bootstrap

**Run this ONCE, before any environment.**

## What it creates

1. **The S3 bucket for Terraform remote state** — versioned, encrypted,
   public access blocked, TLS enforced, with `prevent_destroy` set.
2. **The GitHub Actions OIDC provider and IAM role** — account-level
   resources that only need to exist once.

## Why it is separate

Chicken and egg: every environment stores its state in an S3 bucket, but
something has to create that bucket. This directory runs with **local
state**, so it does not need the bucket to exist first.

## Usage

```bash
cd bootstrap
terraform init

terraform apply \
  -var='github_allowed_subjects=["repo:YOUR-USER/YOUR-REPO:ref:refs/heads/main"]'

terraform output state_bucket_name
terraform output backend_configuration
```

Then paste the bucket name into each `environments/*/backend.tf`.

## Not using GitHub Actions?

```bash
terraform apply -var='enable_github_oidc=false'
```

## State locking

Uses S3 native locking (`use_lockfile = true`), which requires
Terraform >= 1.10. **No DynamoDB table is created** — that pattern is
deprecated by HashiCorp and will be removed in a future release.

## Do not delete this bucket

It holds the only record of what infrastructure exists. Losing it means
Terraform can no longer see resources that keep running and billing you.
Recovery requires `terraform import` for every resource, one at a time.
