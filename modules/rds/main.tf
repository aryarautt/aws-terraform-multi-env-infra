###############################################################################
# RDS MODULE
#
# A managed PostgreSQL instance in the isolated private database subnets.
#
# THE SECRETS PROBLEM, AND HOW THIS MODULE AVOIDS IT
# --------------------------------------------------
# The obvious way to set a database password in Terraform is:
#
#     password = var.db_password        # <-- DO NOT DO THIS
#
# Even if the variable is marked sensitive and passed via an environment
# variable, the value is written in PLAINTEXT into terraform.tfstate. Any
# person or pipeline that can read the state bucket can read the password.
#
# This module instead sets `manage_master_user_password = true`. RDS
# generates the password itself, stores it in AWS Secrets Manager encrypted
# with KMS, and rotates it. The password never passes through Terraform,
# never enters state, and never appears in a plan output.
#
# The application reads it at runtime through the IAM role - see
# modules/iam, where the instance role is granted GetSecretValue on this
# one secret ARN and nothing else.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "rds" })

  # A final snapshot is taken on deletion in production, so an accidental
  # destroy is recoverable. In dev it is skipped - snapshots persist and
  # bill you after everything else is gone.
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-final-${var.final_snapshot_suffix}"
}

###############################################################################
# SUBNET GROUP
#
# Tells RDS which subnets it may place the instance in. Uses the dedicated
# private DB subnets, whose route table has NO internet route at all.
# Requires at least two AZs even for a single-AZ instance, because Multi-AZ
# failover must be possible without rebuilding the subnet group.
###############################################################################

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name_prefix}-db-"
  description = "Private database subnets for ${var.name_prefix}"
  subnet_ids  = var.db_subnet_ids

  tags = merge(local.tags, { Name = "${var.name_prefix}-db-subnet-group" })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# PARAMETER GROUP
#
# Database engine settings. Used here to force TLS on every connection and
# to enable slow-query logging.
###############################################################################

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name_prefix}-pg-"
  family      = var.parameter_group_family
  description = "Parameter group for ${var.name_prefix}"

  # Reject any connection that is not encrypted in transit. Encryption at
  # rest alone is not enough - without this, credentials and query results
  # cross the VPC in cleartext.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Log statements slower than this many milliseconds.
  parameter {
    name         = "log_min_duration_statement"
    value        = tostring(var.log_min_duration_statement)
    apply_method = "immediate"
  }

  # Log every connection and disconnection - useful for auditing.
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# DATABASE INSTANCE
###############################################################################

resource "aws_db_instance" "this" {
  identifier_prefix = "${var.name_prefix}-db-"

  # ---- ENGINE -------------------------------------------------------------
  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Allow AWS to apply minor version patches during the maintenance window.
  # Major upgrades stay manual - they can contain breaking changes.
  auto_minor_version_upgrade = true
  allow_major_version_upgrade = false

  # ---- STORAGE ------------------------------------------------------------
  allocated_storage = var.allocated_storage

  # Autoscale storage up to this ceiling so the database does not hit
  # STORAGE_FULL at 3am. RDS storage can grow but never shrink.
  max_allocated_storage = var.max_allocated_storage

  storage_type = var.storage_type

  # ENCRYPTION AT REST. Costs nothing extra.
  # Critically, this CANNOT be enabled on an existing instance - you would
  # have to snapshot, restore encrypted, and cut over. Always start with it on.
  storage_encrypted = true
  kms_key_id        = var.kms_key_id

  # ---- CREDENTIALS --------------------------------------------------------
  db_name  = var.database_name
  username = var.master_username

  # No `password` argument anywhere. RDS generates and stores it in
  # Secrets Manager. See the module header comment.
  manage_master_user_password = true

  # ---- NETWORKING ---------------------------------------------------------
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  port                   = var.port

  # THE SINGLE MOST IMPORTANT SECURITY SETTING IN THIS FILE.
  # true would give the database a public IP reachable from the internet,
  # leaving only the Security Group between an attacker and your data.
  # Publicly accessible RDS instances are one of the most common causes of
  # real-world data breaches.
  publicly_accessible = false

  # ---- HIGH AVAILABILITY --------------------------------------------------
  # Multi-AZ keeps a synchronous standby replica in a second AZ and fails
  # over automatically in 60-120 seconds. It DOUBLES the instance cost,
  # which is why it is on only in production.
  multi_az = var.multi_az

  # ---- BACKUP AND RECOVERY ------------------------------------------------
  # 0 disables automated backups AND point-in-time recovery entirely.
  # Never 0 in production.
  backup_retention_period = var.backup_retention_period

  # UTC. Chosen to fall outside peak traffic for the region.
  backup_window      = var.backup_window
  maintenance_window = var.maintenance_window

  copy_tags_to_snapshot = true

  # Guards against `terraform destroy` deleting the database. On in
  # production. Note: this must be turned OFF and applied before a genuine
  # teardown - Terraform cannot delete the instance while it is set.
  deletion_protection = var.deletion_protection

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = local.final_snapshot_identifier

  # ---- MONITORING ---------------------------------------------------------
  # Ship database logs to CloudWatch so they survive instance replacement.
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Performance Insights: query-level performance analysis. Free at 7-day
  # retention; longer retention is billed.
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  # OS-level metrics. 0 disables. Billed via CloudWatch Logs.
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  parameter_group_name = aws_db_parameter_group.this.name

  # Apply changes during the maintenance window rather than immediately,
  # since many RDS modifications cause a reboot.
  apply_immediately = var.apply_immediately

  tags = merge(local.tags, { Name = "${var.name_prefix}-db" })

  lifecycle {
    # The engine version drifts when AWS applies an automatic minor
    # upgrade. Ignoring it stops Terraform proposing to downgrade the
    # database on the next plan.
    ignore_changes = [engine_version]
  }
}

###############################################################################
# ENHANCED MONITORING ROLE
###############################################################################

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${var.name_prefix}-rds-mon-"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
