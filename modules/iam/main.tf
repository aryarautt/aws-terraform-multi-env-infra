###############################################################################
# IAM MODULE
#
# Creates the IAM role that EC2 instances assume, following least privilege.
#
# THE CORE IDEA
# -------------
# An EC2 instance needs to call AWS APIs (read from S3, fetch a secret,
# write logs). The wrong way to enable that is to bake an access key into
# the AMI or user data - that key is long-lived, sits in plaintext on disk,
# appears in logs and backups, and is one screenshot away from leaking.
#
# The right way is an INSTANCE PROFILE. AWS injects temporary credentials
# into the instance metadata service. They rotate automatically, expire in
# hours, and never exist as a file anywhere. The AWS SDK picks them up with
# no configuration at all.
#
# This is why the project can honestly claim "no hardcoded AWS credentials".
###############################################################################

locals {
  tags = merge(var.tags, { Module = "iam" })
}

data "aws_caller_identity" "current" {}

###############################################################################
# TRUST POLICY - who is allowed to assume this role
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "AllowEC2ToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    # CONFUSED DEPUTY PROTECTION.
    # Without this condition, the EC2 service principal could in principle
    # be induced to assume this role on behalf of a different AWS account.
    # Pinning the source account means only instances in OUR account can.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name        = "${var.name_prefix}-ec2-role"
  description = "Role assumed by application EC2 instances"

  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  # A permissions boundary caps what this role can EVER be granted, even if
  # someone later attaches AdministratorAccess to it by mistake. It is the
  # difference between "this role has limited permissions right now" and
  # "this role cannot exceed these permissions, full stop".
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.tags, { Name = "${var.name_prefix}-ec2-role" })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = local.tags
}

###############################################################################
# SSM SESSION MANAGER
#
# This AWS-managed policy is what replaces SSH entirely.
#
# With it attached, you can open a shell on an instance that has:
#   - no public IP
#   - no inbound Security Group rule of any kind
#   - no SSH key pair
#
# because the agent dials OUT to the SSM service over HTTPS. Every session
# is authenticated through IAM and logged to CloudTrail.
#
# Using an AWS-managed policy here is a deliberate choice: AWS maintains it
# as the SSM service evolves. Hand-rolling the equivalent means it silently
# breaks when new API actions are introduced.
###############################################################################

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

###############################################################################
# CLOUDWATCH AGENT
#
# Allows the instance to publish custom metrics (memory and disk usage,
# which EC2 does NOT report by default) and to ship application logs.
###############################################################################

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

###############################################################################
# S3 ACCESS - scoped to one bucket, split by operation
###############################################################################

data "aws_iam_policy_document" "s3_access" {
  count = var.s3_bucket_arn != null ? 1 : 0

  # Bucket-level operations act on the bucket ARN itself.
  statement {
    sid    = "ListOwnBucketOnly"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [var.s3_bucket_arn]
  }

  # Object-level operations act on ARNs UNDER the bucket ("/*").
  # Mixing the two in one statement is the single most common cause of
  # mysterious S3 AccessDenied errors - they are different resource types.
  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.s3_bucket_arn}/*"]
  }

  # Explicit deny for unencrypted uploads. An explicit Deny always wins over
  # any Allow, anywhere in IAM - so this cannot be overridden by a broader
  # policy attached later.
  statement {
    sid       = "DenyUnencryptedUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${var.s3_bucket_arn}/*"]

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256", "aws:kms"]
    }
  }
}

resource "aws_iam_role_policy" "s3_access" {
  count = var.s3_bucket_arn != null ? 1 : 0

  name   = "${var.name_prefix}-s3-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access[0].json
}

###############################################################################
# SECRETS MANAGER - read one specific secret
#
# The database password lives in Secrets Manager, created and rotated by
# RDS itself. The application fetches it at runtime. It is never in
# Terraform code, never in Terraform state, and never in an environment
# variable baked into an AMI.
###############################################################################

data "aws_iam_policy_document" "secrets_access" {
  count = var.db_secret_arn != null ? 1 : 0

  statement {
    sid    = "ReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to ONE secret ARN, not "*". If this instance is compromised,
    # the attacker gets this database password - not every secret you own.
    resources = [var.db_secret_arn]
  }

  # RDS-managed secrets are encrypted with a KMS key, so the role also
  # needs permission to decrypt using it.
  dynamic "statement" {
    for_each = var.db_secret_kms_key_arn != null ? [1] : []

    content {
      sid       = "DecryptSecret"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.db_secret_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "secrets_access" {
  count = var.db_secret_arn != null ? 1 : 0

  name   = "${var.name_prefix}-secrets-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.secrets_access[0].json
}
