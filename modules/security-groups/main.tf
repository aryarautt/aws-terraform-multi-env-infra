###############################################################################
# SECURITY GROUPS MODULE
#
# Security Groups are STATEFUL firewalls attached to resources (not subnets).
# "Stateful" means: if you allow an inbound request, the reply is
# automatically allowed back out. You never write a rule for return traffic.
#
# The critical design pattern here is SECURITY GROUP REFERENCING:
# instead of allowing traffic from an IP range, each rule allows traffic
# from another Security Group.
#
#   ALB SG  <-- internet on 80/443
#   APP SG  <-- traffic from ALB SG only        (not from a CIDR)
#   DB  SG  <-- traffic from APP SG only        (not from a CIDR)
#
# Why this matters: the rules stay correct forever. Add ten more application
# servers, replace them, move them to different subnets - as long as they
# carry the app Security Group, the database accepts them, and nothing else
# in the VPC can reach the database at all. With CIDR-based rules you would
# be allowing an entire subnet, including anything else that lands in it.
#
# NOTE: this module uses aws_vpc_security_group_ingress_rule /
# aws_vpc_security_group_egress_rule (one resource per rule) rather than
# inline ingress/egress blocks. Inline blocks are legacy: changing one rule
# forces Terraform to replace the whole rule set, which briefly drops
# traffic. Separate rule resources change independently and each gets its
# own description in the console.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "security-groups" })
}

###############################################################################
# ALB SECURITY GROUP - the only thing exposed to the internet
###############################################################################

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Application Load Balancer: accepts HTTP/HTTPS from the internet"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-alb-sg" })

  # Create the replacement before destroying the old one, so dependent
  # resources are never left pointing at a deleted Security Group.
  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS from the internet.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.enable_https ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = local.tags
}

# HTTP from the internet.
#
# 0.0.0.0/0 is CORRECT here and is not a finding: this is a public web
# application, and the load balancer is the intended public entry point.
# The rule that would be wrong is 0.0.0.0/0 on port 22 (SSH) or on a
# database port - see the app and db Security Groups below, where we
# deliberately never do that.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet (redirected to HTTPS when TLS is enabled)"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80

  tags = local.tags
}

# Egress: the ALB may only talk to the application tier, on the app port.
# A default "allow all outbound" would let a compromised ALB scan the VPC.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward requests to the application tier"

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = local.tags
}

###############################################################################
# APPLICATION SECURITY GROUP - EC2 instances in private subnets
###############################################################################

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Application servers: accept traffic from the ALB only"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-app-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# The ONLY inbound rule. Note referenced_security_group_id, not cidr_ipv4:
# traffic is accepted based on the sender's identity, not its address.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id = aws_security_group.app.id
  description       = "Application traffic from the load balancer only"

  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port

  tags = local.tags
}

# NO SSH RULE.
#
# There is deliberately no port 22 ingress anywhere in this module.
# Administrative access is via AWS Systems Manager Session Manager, which
# works through an outbound HTTPS connection from the instance - so there
# is no inbound port to attack, no bastion host to run and patch, no SSH
# key to distribute or rotate, and every session is logged to CloudTrail.
#
# See modules/iam - the instance role carries AmazonSSMManagedInstanceCore.
#
# Connect with:
#   aws ssm start-session --target i-0123456789abcdef0

# Egress: HTTPS out, for package updates, SSM, Secrets Manager and S3.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out: OS updates, SSM, Secrets Manager, S3, CloudWatch"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = local.tags
}

# HTTP out, for OS package repositories that still use it.
resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP out: OS package repositories"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80

  tags = local.tags
}

# To the database, on the database port only.
resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id = aws_security_group.app.id
  description       = "Database connections"

  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port

  tags = local.tags
}

###############################################################################
# DATABASE SECURITY GROUP - RDS in isolated private subnets
###############################################################################

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Database: accepts connections from the application tier only"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name_prefix}-db-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# One inbound rule. One source. One port.
#
# This is the tightest Security Group in the project, and deliberately so:
# the database is the crown jewels. Combined with the private DB subnets
# having no internet route at all, there are two independent controls
# standing between the database and the outside world.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id = aws_security_group.db.id
  description       = "Database connections from the application tier only"

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port

  tags = local.tags
}

# NO EGRESS RULES.
#
# A database has no legitimate reason to initiate outbound connections.
# Because Security Groups are stateful, replies to inbound queries are
# still returned automatically. Denying egress means that if the database
# were ever compromised, an attacker could not exfiltrate data outward or
# pull down a second-stage payload.
