###############################################################################
# VPC MODULE
#
# Builds a multi-AZ network with three tiers of subnets:
#
#   PUBLIC        - internet-facing. Only the ALB and NAT Gateway live here.
#   PRIVATE APP   - application servers. No inbound internet access.
#                   Outbound internet only via NAT Gateway (optional).
#   PRIVATE DB    - databases. No internet route at all, in either direction.
#
# Design decision: the database tier gets its OWN subnets and its own route
# table with no 0.0.0.0/0 route whatsoever. Even if a Security Group were
# misconfigured, there is physically no path from the database to the
# internet. This is defence in depth - two independent controls, not one.
###############################################################################

locals {
  # Take the first N availability zones in the region. Using a data source
  # rather than hardcoding "ap-south-1a" keeps this module region-portable.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # How many NAT Gateways to build:
  #   enable_nat_gateway = false -> 0  (dev: saves ~$40/month)
  #   single_nat_gateway = true  -> 1  (staging: cheap, but a single point of failure)
  #   single_nat_gateway = false -> one per AZ (production: survives an AZ outage)
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0

  tags = merge(var.tags, { Module = "vpc" })
}

data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones and Wavelength Zones, which do not support
  # all the services we need.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Required for RDS endpoints and VPC endpoints to resolve by name.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpc" })
}

###############################################################################
# INTERNET GATEWAY
#
# The VPC's front door. Attaching it does NOT by itself expose anything -
# a subnet only becomes "public" when its route table points 0.0.0.0/0 here.
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name_prefix}-igw" })
}

###############################################################################
# SUBNETS
#
# CIDR blocks are calculated with cidrsubnet() rather than hardcoded, so the
# same module works with any VPC CIDR without manual arithmetic.
#
# With vpc_cidr = 10.0.0.0/16 and subnet_newbits = 8, each subnet is a /24:
#   public      -> 10.0.0.0/24,  10.0.1.0/24
#   private app -> 10.0.10.0/24, 10.0.11.0/24
#   private db  -> 10.0.20.0/24, 10.0.21.0/24
#
# The gaps (2-9, 12-19) are deliberate: they leave room to add subnets later
# without renumbering, which would force a destroy/recreate of everything.
###############################################################################

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index)
  availability_zone = local.azs[count.index]

  # SECURITY: instances launched here do NOT get a public IP automatically.
  # The ALB and NAT Gateway manage their own public addressing, so nothing
  # else in this subnet needs one. Defaulting to false prevents an accidental
  # `terraform apply` from exposing a server to the internet.
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
    # Tag required by AWS Load Balancer Controller / ELB auto-discovery
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private_app" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, {
    Name                              = "${var.name_prefix}-private-app-${local.azs[count.index]}"
    Tier                              = "private-app"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_subnet" "private_db" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index + 20)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-private-db-${local.azs[count.index]}"
    Tier = "private-db"
  })
}

###############################################################################
# NAT GATEWAY
#
# COST WARNING: this is the most expensive always-on resource in the whole
# project - roughly $0.045-0.056 per hour plus $0.045 per GB processed.
# It is NOT covered by any AWS free tier and never has been.
#
# `enable_nat_gateway = false` in dev avoids ~$40/month. The S3 Gateway
# Endpoint below covers the most common outbound need (S3 access) for free.
###############################################################################

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  })

  # An EIP cannot be allocated until the IGW exists.
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id

  # The NAT Gateway itself must live in a PUBLIC subnet - that is what gives
  # it a route to the internet. The instances it serves live in private ones.
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# ROUTE TABLES
#
# A route table is what actually makes a subnet public or private.
# The subnet resource itself has no notion of "public" - it is entirely
# determined by whether its route table has a path to the Internet Gateway.
###############################################################################

# ---- Public: 0.0.0.0/0 -> Internet Gateway (bidirectional internet) ----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---- Private app: 0.0.0.0/0 -> NAT Gateway (outbound only) ----
#
# One route table PER AZ, even when there is a single shared NAT Gateway.
# Why: if we later switch to one NAT per AZ, the route tables already exist
# and only the target changes - no subnet re-association, no downtime.
resource "aws_route_table" "private_app" {
  count = var.az_count

  vpc_id = aws_vpc.this.id
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-rt-private-app-${local.azs[count.index]}"
  })
}

resource "aws_route" "private_app_nat" {
  count = var.enable_nat_gateway ? var.az_count : 0

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"

  # With a single NAT Gateway every AZ points at index 0.
  # With one per AZ each points at its own, keeping traffic in-AZ
  # (which also avoids cross-AZ data transfer charges).
  nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private_app" {
  count = var.az_count

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# ---- Private DB: NO default route. Deliberately isolated. ----
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-rt-private-db"
  })
}

resource "aws_route_table_association" "private_db" {
  count = var.az_count

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

###############################################################################
# S3 GATEWAY ENDPOINT
#
# Lets private subnets reach S3 over the AWS backbone instead of via the
# NAT Gateway. Two benefits:
#   1. FREE - Gateway endpoints cost nothing (unlike Interface endpoints)
#   2. Traffic never traverses the public internet
#
# This is what allows dev to run with enable_nat_gateway = false and still
# have working S3 access from the application tier.
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    aws_route_table.private_app[*].id,
    [aws_route_table.private_db.id],
  )

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-s3" })
}

###############################################################################
# VPC FLOW LOGS
#
# Records metadata about every network connection in the VPC (source, dest,
# port, bytes, ACCEPT/REJECT). Essential for security investigations and for
# debugging "why can't A reach B" - which is most networking problems.
#
# Disabled in dev by default because log ingestion costs money at volume.
###############################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = local.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    # LEAST PRIVILEGE: scoped to this log group only, not "*".
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.name_prefix}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(local.tags, { Name = "${var.name_prefix}-flow-logs" })
}

###############################################################################
# DEFAULT SECURITY GROUP LOCKDOWN
#
# Every VPC ships with a default Security Group that allows all traffic
# between anything using it. AWS security benchmarks (CIS) require it to be
# empty. This resource adopts it and strips every rule.
###############################################################################

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  # No ingress or egress blocks = deny everything.

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-default-sg-DO-NOT-USE"
  })
}
