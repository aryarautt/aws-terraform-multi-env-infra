###############################################################################
# S3 MODULE
#
# An application storage bucket, locked down by default.
#
# Publicly readable S3 buckets have caused some of the largest data
# exposures on record. Every one of them was a default left unchanged.
# This module inverts that: access is denied unless explicitly granted.
#
# NOTE ON RESOURCE LAYOUT
# -----------------------
# Bucket settings used to be inline blocks inside aws_s3_bucket. Since AWS
# provider v4 each concern is a SEPARATE resource (versioning, encryption,
# public access block, lifecycle, policy). Tutorials still showing
# `versioning { enabled = true }` inside aws_s3_bucket are pre-v4 and will
# not work. The split is better anyway - each setting changes independently
# and shows up clearly in a plan.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "s3" })
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  # S3 bucket names are GLOBALLY unique across every AWS account on earth,
  # so a plain name like "app-data" will always collide. The environment
  # config appends the account ID and region to guarantee uniqueness.
  bucket = var.bucket_name

  # force_destroy = true lets `terraform destroy` delete a bucket that
  # still holds objects. Convenient in dev, dangerous in production - there
  # it stays false so a destroy fails loudly rather than deleting data.
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = var.bucket_name })
}

###############################################################################
# BLOCK ALL PUBLIC ACCESS
#
# The most important resource in this file. All four settings on.
# This overrides any ACL or bucket policy that would otherwise grant public
# access - a belt-and-braces control that cannot be defeated by a mistake
# elsewhere.
###############################################################################

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  # Reject new public ACLs.
  block_public_acls = true
  # Ignore any public ACL already present.
  ignore_public_acls = true
  # Reject bucket policies that grant public access.
  block_public_policy = true
  # Deny all public and cross-account access granted by a policy.
  restrict_public_buckets = true
}

###############################################################################
# OWNERSHIP CONTROLS
#
# Disables ACLs entirely. ACLs are a legacy access mechanism that predates
# IAM and is easy to misconfigure. BucketOwnerEnforced makes IAM policies
# the single source of truth for who can do what.
###############################################################################

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

###############################################################################
# ENCRYPTION AT REST
###############################################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3 (AES256) is free. SSE-KMS gives you an audit trail of every
      # decrypt and per-key access control, but costs per request.
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }

    # S3 Bucket Keys cut KMS request costs by up to 99% by caching a
    # data key rather than calling KMS for every single object.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

###############################################################################
# VERSIONING
#
# Keeps every version of every object. This is the defence against both
# accidental deletion and ransomware - an attacker who encrypts your
# objects has not destroyed the previous versions.
###############################################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

###############################################################################
# LIFECYCLE RULES
#
# Versioning without lifecycle rules means storage grows forever and the
# bill grows with it. These rules expire old versions and clean up failed
# multipart uploads, which are invisible in the console but still billed.
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.enable_lifecycle_rules ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Required by provider v5+ so lifecycle rules apply predictably
  # regardless of versioning state.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = var.transition_to_ia_days > 0 ? [1] : []

    content {
      id     = "transition-to-infrequent-access"
      status = "Enabled"

      filter {}

      transition {
        days          = var.transition_to_ia_days
        storage_class = "STANDARD_IA"
      }
    }
  }
}

###############################################################################
# BUCKET POLICY
#
# Two explicit denials. An explicit Deny in IAM overrides every Allow,
# anywhere - including future policies someone attaches by mistake.
###############################################################################

data "aws_iam_policy_document" "bucket_policy" {
  # 1. Refuse any request not made over TLS.
  #    Without this, an HTTP request would be served happily and the
  #    object contents would cross the network in cleartext.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # 2. Refuse uploads that are not server-side encrypted.
  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  # 3. Optional: allow the ALB service account to write access logs.
  dynamic "statement" {
    for_each = var.enable_alb_access_logs ? [1] : []

    content {
      sid    = "AllowALBAccessLogs"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
      }

      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/alb/*"]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  # The public access block must be in place BEFORE the policy is applied,
  # or S3 may reject the policy as granting public access.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
