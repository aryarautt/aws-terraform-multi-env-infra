###############################################################################
# ENVIRONMENT ROOT MODULE
#
# This file contains NO raw AWS resources. It only calls the reusable
# modules in ../../modules/ and wires their outputs into each other's
# inputs.
#
# That separation is the whole point of the repository layout:
#
#   modules/      = HOW to build something (identical for every environment)
#   environments/ = WHAT to build and HOW BIG (differs per environment)
#
# dev, staging and production all use this same file. The only differences
# live in terraform.tfvars and backend.tf. That is what guarantees the
# environments cannot drift apart structurally - the failure mode the
# problem statement describes.
#
# DEPENDENCY ORDER (Terraform works this out itself from the references,
# but it helps to see it):
#
#   vpc -> security-groups -> s3 -> rds -> iam -> alb -> ec2 -> cloudwatch
###############################################################################

locals {
  # Every resource name in the project starts with this.
  # e.g. "aws-tf-infra-dev-vpc", "aws-tf-infra-dev-alb"
  name_prefix = "${var.project_name}-${var.environment}"

  # Defined here, not inside a module, and passed to BOTH the cloudwatch
  # module (which creates it) and the ec2 module (which ships logs to it).
  # Passing a plain string breaks what would otherwise be a dependency
  # cycle between those two modules.
  log_group_name = "/aws/ec2/${local.name_prefix}/application"

  # S3 bucket names are globally unique across every AWS account, so the
  # account ID and region are appended.
  app_bucket_name = "${local.name_prefix}-app-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  # Applied to every resource via the provider's default_tags, plus passed
  # explicitly to modules that build their own tag maps.
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
    Repository  = var.repository_url
  }
}

data "aws_caller_identity" "current" {}

###############################################################################
# 1. NETWORK
###############################################################################

module "vpc" {
  source = "../../modules/vpc"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  vpc_cidr = var.vpc_cidr
  az_count = var.az_count

  # THE PRIMARY COST LEVER.
  # A NAT Gateway costs roughly $40/month and is not covered by any free
  # tier. dev sets this to false; the S3 Gateway Endpoint below still
  # gives instances free access to S3.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_s3_endpoint = true

  enable_flow_logs         = var.enable_flow_logs
  flow_logs_retention_days = var.log_retention_days

  tags = local.common_tags
}

###############################################################################
# 2. SECURITY GROUPS
###############################################################################

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

  app_port     = var.app_port
  db_port      = var.db_port
  enable_https = var.certificate_arn != null

  tags = local.common_tags
}

###############################################################################
# 3. APPLICATION STORAGE
###############################################################################

module "s3" {
  source = "../../modules/s3"

  bucket_name = local.app_bucket_name

  # dev allows a bucket with objects in it to be destroyed, so teardown is
  # clean. Production does not - a destroy there should fail loudly rather
  # than silently delete data.
  force_destroy = var.s3_force_destroy

  enable_versioning                  = var.s3_enable_versioning
  enable_lifecycle_rules             = true
  noncurrent_version_expiration_days = var.s3_noncurrent_version_days

  enable_alb_access_logs = var.enable_alb_access_logs

  tags = local.common_tags
}

###############################################################################
# 4. DATABASE
#
# Created before the IAM module, because the IAM role needs the ARN of the
# Secrets Manager secret that RDS generates.
###############################################################################

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"

  name_prefix = local.name_prefix

  # PRIVATE DATABASE SUBNETS - a route table with no internet route at all.
  db_subnet_ids     = module.vpc.private_db_subnet_ids
  security_group_id = module.security_groups.db_security_group_id

  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  parameter_group_family = var.db_parameter_group_family
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  max_allocated_storage  = var.db_max_allocated_storage
  database_name          = var.db_name
  port                   = var.db_port

  # Environment-specific reliability settings.
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  final_snapshot_suffix   = var.db_final_snapshot_suffix

  performance_insights_enabled = var.db_performance_insights
  monitoring_interval          = var.db_monitoring_interval

  tags = local.common_tags
}

###############################################################################
# 5. IAM
#
# Grants the EC2 instances exactly two things: read/write on the one
# application bucket, and read on the one database secret.
###############################################################################

module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix

  s3_bucket_arn = module.s3.bucket_arn

  # try() handles the case where RDS is disabled - the outputs do not exist
  # and the IAM policies for secrets are simply not created.
  db_secret_arn         = try(module.rds[0].db_secret_arn, null)
  db_secret_kms_key_arn = try(module.rds[0].db_secret_kms_key_id, null)

  permissions_boundary_arn = var.permissions_boundary_arn

  tags = local.common_tags
}

###############################################################################
# 6. LOAD BALANCER
#
# Created before EC2, because the Auto Scaling Group needs the target
# group ARN in order to register instances with it.
###############################################################################

module "alb" {
  source = "../../modules/alb"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id

  # PUBLIC subnets - the only internet-facing component in the system.
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id

  app_port          = var.app_port
  health_check_path = var.health_check_path

  certificate_arn = var.certificate_arn

  enable_deletion_protection = var.alb_deletion_protection
  access_logs_bucket         = var.enable_alb_access_logs ? module.s3.bucket_id : null

  tags = local.common_tags
}

###############################################################################
# 7. COMPUTE
###############################################################################

module "ec2" {
  source = "../../modules/ec2"

  name_prefix  = local.name_prefix
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  # PRIVATE APPLICATION SUBNETS. No public IP, no inbound internet route.
  private_subnet_ids = module.vpc.private_app_subnet_ids
  security_group_id  = module.security_groups.app_security_group_id

  # This is what replaces access keys entirely.
  instance_profile_name = module.iam.ec2_instance_profile_name

  target_group_arns = [module.alb.target_group_arn]
  log_group_name    = local.log_group_name

  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size
  app_port         = var.app_port

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  enable_detailed_monitoring = var.enable_detailed_monitoring
  enable_autoscaling         = var.enable_autoscaling
  target_cpu_utilization     = var.target_cpu_utilization

  tags = local.common_tags
}

###############################################################################
# 8. MONITORING
#
# Last, because its alarms reference the ASG, the ALB and the database.
###############################################################################

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  log_group_name     = local.log_group_name
  log_retention_days = var.log_retention_days

  create_sns_topic = true
  alarm_email      = var.alarm_email

  autoscaling_group_name = module.ec2.autoscaling_group_name

  # CloudWatch identifies load balancers by the "suffix" of the ARN rather
  # than the full ARN. These regex replacements extract it.
  alb_arn_suffix          = replace(module.alb.alb_arn, "/^.*?(app/.*)$/", "$1")
  target_group_arn_suffix = replace(module.alb.target_group_arn, "/^.*?(targetgroup/.*)$/", "$1")

  db_instance_id = try(module.rds[0].db_instance_id, null)

  cpu_alarm_threshold = var.cpu_alarm_threshold
  create_dashboard    = var.create_dashboard

  tags = local.common_tags
}
