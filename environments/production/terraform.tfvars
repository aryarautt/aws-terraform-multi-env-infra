###############################################################################
# PRODUCTION ENVIRONMENT VALUES
#
# PRODUCTION PHILOSOPHY: availability, durability and safety first.
# Cost is a consideration, not the deciding one.
#
# Every setting that differs from dev is a deliberate reliability or
# security decision, annotated below with WHY.
#
# ###########################################################################
# COST WARNING - READ BEFORE APPLYING
# ###########################################################################
# This configuration is materially more expensive than dev:
#
#   2x NAT Gateway     ~$80/month   (one per AZ, survives an AZ outage)
#   Multi-AZ RDS       ~$50/month   (db.t4g.medium, doubled for the standby)
#   3x t3.medium EC2   ~$90/month
#   ALB                ~$20/month
#   -------------------------------------------------------------------
#   ROUGHLY $240/month if left running.
#
# For a learning project, apply this ONCE to prove it works, capture the
# evidence, and destroy it the same session. Do NOT leave it running.
#
# Note that deletion_protection is ON below. To tear this down you must
# first set alb_deletion_protection and db_deletion_protection to false,
# apply that change, and only then destroy. That friction is intentional -
# it is what stops an accidental production teardown.
# ###########################################################################
###############################################################################

environment = "production"
aws_region  = "ap-south-1"
aws_profile = "terraform"

project_name   = "aws-tf-infra"
owner          = "platform-team"
cost_center    = "production"
repository_url = "https://github.com/aryarautt/aws-terraform-multi-env-infra"

# ---- Network ----------------------------------------------------------------
vpc_cidr = "10.2.0.0/16"

# 2 AZs minimum. Raise to 3 for higher availability at proportionally
# higher NAT Gateway cost.
az_count = 2

# ONE NAT GATEWAY PER AZ.
#
# With a single shared gateway, losing its AZ takes out egress for every
# private subnet in the VPC - including the ones in healthy AZs. That turns
# a single-AZ incident into a full outage, defeating the entire multi-AZ
# design. Production pays roughly $40/month extra to avoid that.
enable_nat_gateway = true
single_nat_gateway = false

# Flow logs on: required for security investigations and for answering
# "what talked to what" after an incident.
enable_flow_logs = true

# ---- Compute ----------------------------------------------------------------
instance_type    = "t3.medium"
root_volume_size = 30

# min_size = 2 so the system survives losing one instance without any
# window of reduced capacity while a replacement boots.
asg_min_size         = 2
asg_max_size         = 6
asg_desired_capacity = 3

enable_autoscaling     = true
target_cpu_utilization = 60

# 1-minute metrics. During an incident, 5-minute granularity means you are
# reacting to data that is already stale.
enable_detailed_monitoring = true

# ---- Load balancer ----------------------------------------------------------
# REQUIRED FOR PRODUCTION.
#
# Request a free public certificate in AWS Certificate Manager for a domain
# you control, then paste its ARN here. The alb module will then create an
# HTTPS listener and permanently redirect all HTTP traffic to it.
#
# Left null, production serves plain HTTP - unacceptable for anything
# handling real user data.
#
# certificate_arn = "arn:aws:acm:ap-south-1:XXXXXXXXXXXX:certificate/..."
certificate_arn = null

# ON. Blocks `terraform destroy` from deleting the load balancer.
# A deliberate two-step process is required to remove it.
alb_deletion_protection = true

# ON. Access logs are the primary record of what requests were served,
# from where, with what response - essential for incident investigation
# and for detecting abuse.
enable_alb_access_logs = true

# ---- Database ---------------------------------------------------------------
enable_rds = true

db_instance_class        = "db.t4g.medium"
db_allocated_storage     = 50
db_max_allocated_storage = 500

# MULTI-AZ: ON.
# Maintains a synchronous standby replica in a second Availability Zone
# and fails over automatically in 60-120 seconds. Doubles the instance
# cost. This is the difference between a hardware failure being a blip and
# being an outage.
db_multi_az = true

# 30 days of automated backups, which also provides 30 days of
# point-in-time recovery to any second in that window.
db_backup_retention_period = 30

# ON. Terraform physically cannot delete this instance while set.
db_deletion_protection = true

# FALSE. Always take a final snapshot before deletion, so an accidental
# teardown is recoverable.
#
# NOTE: the snapshot persists after destroy and continues to incur storage
# charges. Delete it deliberately once you are certain it is not needed.
db_skip_final_snapshot   = false
db_final_snapshot_suffix = "v1"

db_performance_insights = true
db_monitoring_interval  = 30

# ---- Storage ----------------------------------------------------------------
# FALSE. A destroy against a bucket containing objects will FAIL rather
# than silently delete production data. Emptying it must be a conscious act.
s3_force_destroy = false

s3_enable_versioning       = true
s3_noncurrent_version_days = 90

# ---- Monitoring -------------------------------------------------------------
# 90 days. Long enough to investigate an incident discovered weeks later
# and to satisfy most basic compliance requirements.
log_retention_days = 90

# Tighter than dev - production should be alerting before users notice.
cpu_alarm_threshold = 75

create_dashboard = true

# STRONGLY RECOMMENDED for production: alarms nobody receives are not
# monitoring.
# alarm_email = "oncall@example.com"
