###############################################################################
# EC2 MODULE
#
# Provisions the application tier as a Launch Template + Auto Scaling Group
# rather than standalone aws_instance resources.
#
# WHY AN ASG INSTEAD OF PLAIN INSTANCES
# -------------------------------------
#   1. Self-healing. If an instance fails its ALB health check, the ASG
#      terminates it and launches a replacement. No human involved.
#   2. Multi-AZ by construction. The ASG spreads instances across the
#      private subnets it is given, so an AZ outage does not take the app
#      down.
#   3. Scaling is a number. desired_capacity is a variable - dev runs 1,
#      production runs 3, from identical code.
#   4. Immutable updates. Changing the Launch Template triggers a rolling
#      instance refresh instead of mutating live servers in place.
#
# A bare aws_instance can do none of these things.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "ec2" })
}

###############################################################################
# AMI LOOKUP
#
# A data source, not a hardcoded AMI ID. AMI IDs differ per region and
# change every time AWS publishes a patched image - hardcoding one means
# the code breaks in another region and silently goes stale on security
# updates.
###############################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################################################################
# LAUNCH TEMPLATE
#
# The blueprint the Auto Scaling Group stamps out: which AMI, which
# instance type, which IAM role, which Security Group, what to run at boot.
###############################################################################

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  description   = "Launch template for ${var.name_prefix} application instances"
  image_id      = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # Attaching the instance profile here is what gives instances temporary,
  # auto-rotating AWS credentials. No access keys anywhere.
  iam_instance_profile {
    name = var.instance_profile_name
  }

  vpc_security_group_ids = [var.security_group_id]

  # ---- IMDSv2 ENFORCEMENT -------------------------------------------------
  # The Instance Metadata Service is what hands out those temporary
  # credentials. IMDSv1 answered any HTTP GET to 169.254.169.254, which made
  # it reachable through a Server-Side Request Forgery bug in the
  # application - the root cause of several large cloud breaches.
  #
  # http_tokens = "required" forces IMDSv2, which needs a PUT request to
  # obtain a session token first. SSRF cannot issue a PUT, so the whole
  # attack class is closed.
  #
  # hop_limit = 1 stops containers on the host from reaching the metadata
  # service through the instance's network namespace.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # ---- ROOT VOLUME --------------------------------------------------------
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = var.root_volume_size
      volume_type = "gp3"

      # Encryption at rest. gp3 + encryption costs nothing extra, so there
      # is no reason ever to leave this off.
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    # Detailed monitoring reports metrics every 1 minute instead of 5.
    # It is billed per instance, so it is off in dev and on in production.
    enabled = var.enable_detailed_monitoring
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    app_port     = var.app_port
    environment  = var.environment
    project_name = var.project_name
    aws_region   = var.aws_region
    log_group    = var.log_group_name
  }))

  # Tags on the template itself do not propagate to launched instances -
  # these tag_specifications blocks are what do that.
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name_prefix}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name_prefix}-app-volume" })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# AUTO SCALING GROUP
###############################################################################

resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.name_prefix}-asg-"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  # Instances are placed ONLY in private application subnets. There is no
  # code path in this module that can put a server in a public subnet.
  vpc_zone_identifier = var.private_subnet_ids

  target_group_arns = var.target_group_arns

  # "ELB" means the ASG trusts the load balancer's health check, not just
  # the EC2 hypervisor status check. An instance whose application has
  # crashed still passes the EC2 check but fails the ELB one - only this
  # setting will replace it.
  health_check_type         = length(var.target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # ---- ROLLING UPDATES ----------------------------------------------------
  # When the Launch Template changes (new AMI, new user data), replace
  # instances gradually while keeping min_healthy_percentage in service.
  # This is immutable infrastructure: servers are replaced, never patched
  # in place.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = var.instance_refresh_min_healthy_percentage
      instance_warmup        = var.health_check_grace_period
    }
  }

  # Spread instances evenly across AZs rather than packing them.
  # Without this the ASG can put every instance in one AZ, silently
  # defeating the multi-AZ design.
  availability_zone_distribution {
    capacity_distribution_strategy = "balanced-best-effort"
  }

  dynamic "tag" {
    for_each = merge(local.tags, { Name = "${var.name_prefix}-app" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true

    # desired_capacity is managed by scaling policies at runtime. Ignoring
    # it here stops Terraform from scaling the fleet back down to the
    # configured value on every apply.
    ignore_changes = [desired_capacity]
  }

  timeouts {
    delete = "15m"
  }
}

###############################################################################
# TARGET TRACKING SCALING POLICY
#
# Declarative scaling: "keep average CPU near 60%". AWS works out when to
# add or remove instances. Far simpler and less brittle than hand-written
# step-scaling rules with CloudWatch alarms.
###############################################################################

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  count = var.enable_autoscaling ? 1 : 0

  name                   = "${var.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.target_cpu_utilization
  }
}
