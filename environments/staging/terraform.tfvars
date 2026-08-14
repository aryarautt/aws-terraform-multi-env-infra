###############################################################################
# STAGING ENVIRONMENT VALUES
#
# STAGING PHILOSOPHY: production's architecture at a smaller scale.
#
# The point of staging is to catch problems that only appear with a
# production-shaped topology. So the things that change BEHAVIOUR match
# production (NAT Gateway present, backups on, monitoring on), while the
# things that only change CAPACITY are sized down (instance types, count).
#
# A staging environment that differs structurally from production tests
# nothing useful - that is exactly the "inconsistent environments" problem
# this project exists to solve.
###############################################################################

environment = "staging"
aws_region  = "ap-south-1"
aws_profile = "terraform"

project_name   = "aws-tf-infra"
owner          = "shravani"
cost_center    = "engineering"
repository_url = "https://github.com/aryarautt/aws-terraform-multi-env-infra"

# ---- Network ----------------------------------------------------------------
# Different CIDR from dev and production - no overlap, so these VPCs could
# be peered later without renumbering.
vpc_cidr = "10.1.0.0/16"
az_count = 2

# NAT Gateway IS enabled here, because its absence changes application
# behaviour: outbound calls to third-party APIs, package installs, and
# webhook deliveries all fail without it. Staging must exercise that path.
#
# single_nat_gateway = true keeps it to ONE gateway (~$40/month instead of
# ~$80). The trade-off is that an AZ failure takes out egress for the whole
# environment - acceptable in staging, not in production.
enable_nat_gateway = true
single_nat_gateway = true

# Flow logs on, so security tooling and log pipelines are exercised
# before production depends on them.
enable_flow_logs = true

# ---- Compute ----------------------------------------------------------------
instance_type        = "t3.small"
root_volume_size     = 30
asg_min_size         = 2
asg_max_size         = 4
asg_desired_capacity = 2

# Autoscaling enabled so scaling policies are validated before production.
enable_autoscaling     = true
target_cpu_utilization = 65

enable_detailed_monitoring = true

# ---- Load balancer ----------------------------------------------------------
# Set this to a real ACM certificate ARN to test the HTTPS path.
# Leaving it null means staging serves HTTP only, which does NOT exercise
# TLS termination, HSTS, or mixed-content behaviour.
certificate_arn = null

# Off, so staging can still be destroyed for cost control.
alb_deletion_protection = false

# On, because access logs are part of what production relies on for
# incident investigation.
enable_alb_access_logs = true

# ---- Database ---------------------------------------------------------------
enable_rds = true

db_instance_class        = "db.t4g.small"
db_allocated_storage     = 20
db_max_allocated_storage = 100

# Single AZ. Multi-AZ doubles cost; failover behaviour is verified in
# production, and staging accepts the downtime risk.
db_multi_az = false

# 7 days - enough to genuinely practise a point-in-time restore.
db_backup_retention_period = 7

db_deletion_protection = false
db_skip_final_snapshot = true

# Free at 7-day retention, and worth having so query performance problems
# surface here rather than in production.
db_performance_insights = true
db_monitoring_interval  = 60

# ---- Storage ----------------------------------------------------------------
s3_force_destroy           = true
s3_enable_versioning       = true
s3_noncurrent_version_days = 30

# ---- Monitoring -------------------------------------------------------------
log_retention_days  = 30
cpu_alarm_threshold = 80
create_dashboard    = true

# alarm_email = "you@example.com"
