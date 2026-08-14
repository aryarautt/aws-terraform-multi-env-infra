###############################################################################
# BOOTSTRAP
#
# Solves the chicken-and-egg problem of Terraform remote state.
#
# THE PROBLEM
# -----------
# Every environment stores its state in an S3 bucket. But that bucket has
# to be created by something. If Terraform created it while also storing
# its own state in it, the backend would need to exist before it exists.
#
# THE SOLUTION
# ------------
# This directory runs ONCE, with LOCAL state, and creates:
#   1. The S3 bucket that every environment will use as its backend
#   2. The GitHub OIDC provider and CI/CD role (account-level, created once)
#
# After the bucket exists, every environment points its backend at it.
#
# STATE LOCKING - IMPORTANT VERSION NOTE
# --------------------------------------
# Terraform 1.10 introduced NATIVE S3 state locking via `use_lockfile = true`,
# which uses S3 conditional writes. The older pattern of provisioning a
# DynamoDB table purely to hold a lock is now DEPRECATED by HashiCorp and
# will be removed in a future release.
#
# Most tutorials online still teach the DynamoDB approach. This project does
# not create a DynamoDB table, and that is deliberate.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70, < 7.0"
    }
  }

  # NO backend block. This directory intentionally uses local state.
  #
  # Commit bootstrap/terraform.tfstate to git ONLY if it contains no
  # secrets (this one does not). The safer alternative, and what this
  # project's .gitignore assumes, is to keep it out of git and treat the
  # bootstrap as reproducible: `terraform import` can re-adopt the bucket
  # if the local state is ever lost.
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Component   = "bootstrap"
      Environment = "shared"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Account ID and region make the bucket name globally unique.
  # S3 bucket names must be unique across every AWS account in the world.
  state_bucket_name = coalesce(
    var.state_bucket_name,
    "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )
}

###############################################################################
# TERRAFORM STATE BUCKET
###############################################################################

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  # NEVER true. This bucket holds the only record of what infrastructure
  # exists. Deleting it means Terraform loses track of every resource it
  # manages - they keep running and billing you, but Terraform can no
  # longer see or destroy them.
  force_destroy = false

  tags = {
    Name        = local.state_bucket_name
    Description = "Terraform remote state - DO NOT DELETE"
  }

  lifecycle {
    # A second safety net: Terraform itself will refuse to destroy this,
    # even if someone removes the resource block and runs apply.
    prevent_destroy = true
  }
}

# VERSIONING IS NOT OPTIONAL HERE.
#
# State corruption happens - a failed apply, a network drop mid-write, a
# botched manual edit. Versioning is the only way to roll back to a known
# good state file. Without it, a corrupted state means rebuilding the
# state by hand with `terraform import`, resource by resource.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# STATE FILES CONTAIN SECRETS.
#
# Terraform writes resource attributes into state in plaintext - including
# values marked `sensitive` in the configuration. Encryption at rest is
# mandatory, not a nice-to-have.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null
  }
}

# The state bucket must never, under any circumstances, be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Keep old state versions for a while, then expire them. Without this,
# every apply adds a version forever and storage grows without limit.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      # 90 days of state history is a reasonable recovery window.
      noncurrent_days = var.state_version_retention_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Deny any non-TLS access to state.
data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

###############################################################################
# GITHUB ACTIONS OIDC
#
# Lets GitHub Actions authenticate to AWS with NO stored AWS credentials.
#
# THE OLD WAY (do not do this):
#   Create an IAM user, generate an access key, paste it into GitHub
#   Secrets. That key is long-lived, works from anywhere on the internet,
#   and if the repo or a workflow log leaks it, an attacker has your
#   account until you notice and rotate.
#
# THE OIDC WAY:
#   GitHub issues a short-lived, cryptographically signed token that
#   asserts "this is repo X, branch Y, workflow Z". AWS validates the
#   signature against GitHub's public keys and exchanges it for temporary
#   credentials. Nothing secret is ever stored. Credentials expire in
#   under an hour. The trust policy pins WHICH repository and WHICH branch
#   may assume the role.
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # NOTE: since 2023 AWS validates GitHub's certificate against its own
  # trusted CA store, so this thumbprint is no longer security-critical.
  # It remains a required API field.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_assume" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    # The audience must be AWS STS.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # THE CRITICAL CONDITION.
    # `sub` identifies the repository and ref. Without pinning it, ANY
    # GitHub repository on the entire platform could assume this role.
    #
    # StringLike allows patterns such as:
    #   repo:owner/name:ref:refs/heads/main        - only the main branch
    #   repo:owner/name:pull_request               - only pull requests
    #   repo:owner/name:environment:production     - only that environment
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_allowed_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0

  name        = "${var.project_name}-github-actions"
  description = "Assumed by GitHub Actions via OIDC. No long-lived credentials."

  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume[0].json
  max_session_duration = 3600

  tags = {
    Name = "${var.project_name}-github-actions"
  }
}

# LEARNING-ONLY SHORTCUT - clearly labelled.
#
# PowerUserAccess grants broad permissions but explicitly EXCLUDES IAM
# write access, so a compromised pipeline cannot escalate its own
# privileges or create new admin users. That is meaningfully safer than
# AdministratorAccess.
#
# THE PRODUCTION-SAFE ALTERNATIVE: replace this with a hand-written policy
# listing only the actions the pipeline actually needs, generated from
# CloudTrail data after a few real runs (IAM Access Analyzer can do this
# for you). See docs/SECURITY.md.
resource "aws_iam_role_policy_attachment" "github_actions" {
  count = var.enable_github_oidc ? 1 : 0

  role       = aws_iam_role.github_actions[0].name
  policy_arn = var.github_actions_policy_arn
}

# The pipeline also needs IAM permissions, because the environments create
# IAM roles for EC2. Scoped by name prefix rather than granted wholesale.
data "aws_iam_policy_document" "github_actions_iam" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid    = "ManageProjectIAMRoles"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:PassRole",
    ]

    # Scoped to this project's naming convention only. The pipeline cannot
    # touch any other role in the account.
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.project_name}-*",
    ]
  }

  statement {
    sid    = "ReadOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_iam" {
  count = var.enable_github_oidc ? 1 : 0

  name   = "manage-project-iam"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_iam[0].json
}

# Access to the state bucket, so the pipeline can read and write state.
data "aws_iam_policy_document" "github_actions_state" {
  count = var.enable_github_oidc ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid    = "ReadWriteState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_actions_state" {
  count = var.enable_github_oidc ? 1 : 0

  name   = "terraform-state-access"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_state[0].json
}
