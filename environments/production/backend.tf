###############################################################################
# REMOTE STATE BACKEND - production
#
# WHY REMOTE STATE
# ----------------
# terraform.tfstate is Terraform's record of every resource it manages and
# the real AWS IDs behind them. Kept only on a laptop it is:
#   - unshareable  - a teammate applying would try to recreate everything
#   - unsafe       - two people applying at once corrupts it
#   - fragile      - a lost laptop means Terraform no longer knows what
#                    exists, while those resources keep running and billing
#   - insecure     - state contains resource attributes in plaintext
#
# STATE LOCKING - VERSION-SENSITIVE DETAIL
# ----------------------------------------
# `use_lockfile = true` enables Terraform's NATIVE S3 locking, which uses
# S3 conditional writes and requires Terraform 1.10 or newer.
#
# The older pattern - provisioning a DynamoDB table and setting
# `dynamodb_table = "..."` - is DEPRECATED by HashiCorp and will be removed
# in a future release. Most tutorials still teach it. This project does not
# use it, on purpose.
#
# ENVIRONMENT ISOLATION
# ---------------------
# All three environments share one bucket but use DIFFERENT `key` values.
# Separate state files mean a `terraform destroy` in dev is physically
# incapable of touching production - it is reading a different file and
# has no knowledge that production resources exist.
#
# BEFORE FIRST USE
# ----------------
#   1. cd ../../bootstrap && terraform init && terraform apply
#   2. Copy the bucket name from its output into `bucket` below
#   3. cd back here and run: terraform init
###############################################################################

terraform {
  backend "s3" {
    # CHANGE THIS to the bucket name output by the bootstrap step.
    bucket = "CHANGE-ME-tfstate-ACCOUNTID-ap-south-1"

    # Unique per environment. This is what isolates the state files.
    key = "production/terraform.tfstate"

    region = "ap-south-1"

    # Encrypt the state file at rest in S3.
    encrypt = true

    # Native S3 state locking. Requires Terraform >= 1.10.
    # Replaces the deprecated dynamodb_table approach.
    use_lockfile = true
  }
}
