###############################################################################
# APPLICATION LOAD BALANCER MODULE
#
# The ALB is the single public entry point to the whole system. It is the
# ONLY component with an internet-facing address; everything behind it sits
# in private subnets with no route in from outside.
#
# REQUEST PATH
#   1. User resolves the ALB DNS name -> AWS-managed public IPs
#   2. Request hits an ALB node in a PUBLIC subnet
#   3. ALB Security Group allows 80/443 from the internet
#   4. ALB picks a HEALTHY target from the target group
#   5. ALB opens a NEW connection to that instance in a PRIVATE subnet
#   6. App Security Group allows the connection because it comes from the
#      ALB's Security Group
#
# Step 5 is the important one: the client never connects to the instance.
# The ALB terminates the client connection and makes its own. That is why
# the instances need no public IP and no inbound internet rule.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "alb" })
}

###############################################################################
# LOAD BALANCER
###############################################################################

resource "aws_lb" "this" {
  name_prefix = substr(var.name_prefix, 0, 6)

  # internal = false makes this internet-facing. This is the ONE resource
  # in the project where that is correct.
  internal           = false
  load_balancer_type = "application"

  security_groups = [var.security_group_id]

  # PUBLIC subnets - the ALB needs a route to the Internet Gateway.
  # It requires at least two subnets in different AZs; AWS places a
  # load balancer node in each and DNS round-robins between them.
  subnets = var.public_subnet_ids

  # Blocks `terraform destroy` from deleting the load balancer.
  # ON in production, off elsewhere - otherwise you cannot tear down dev.
  enable_deletion_protection = var.enable_deletion_protection

  # Spread across AZs; keeps working if one AZ fails.
  enable_cross_zone_load_balancing = true

  # Must exceed the application's own keep-alive timeout, or the ALB will
  # close connections the backend still considers open, producing
  # intermittent 502s that are miserable to debug.
  idle_timeout = var.idle_timeout

  # Drop malformed requests instead of forwarding them - defends against
  # HTTP request-smuggling attacks.
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []

    content {
      bucket  = var.access_logs_bucket
      prefix  = "alb"
      enabled = true
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-alb" })
}

###############################################################################
# TARGET GROUP
#
# The pool of instances the ALB forwards to, plus the health check that
# decides which of them are eligible.
###############################################################################

resource "aws_lb_target_group" "this" {
  name_prefix = substr(var.name_prefix, 0, 6)

  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # "instance" registers by instance ID; the ASG handles registration and
  # deregistration automatically as it scales.
  target_type = "instance"

  # How long to wait for in-flight requests to finish before removing a
  # terminating instance. Too short and users see errors during deploys.
  deregistration_delay = var.deregistration_delay

  # ---- HEALTH CHECK -------------------------------------------------------
  # This is the number one source of "my ALB returns 503" for beginners.
  # A target only receives traffic after healthy_threshold consecutive
  # successes. If the path 404s, or the Security Group blocks the ALB, or
  # the app is still booting, the target stays unhealthy and the ALB has
  # nowhere to send requests.
  health_check {
    enabled = true

    # A dedicated lightweight endpoint - NOT "/" and never anything that
    # queries the database.
    path     = var.health_check_path
    port     = "traffic-port"
    protocol = "HTTP"

    # Poll every N seconds.
    interval = var.health_check_interval

    # Give up on a single check after this long. Must be < interval.
    timeout = var.health_check_timeout

    # Consecutive successes before a target is put into service.
    healthy_threshold = var.healthy_threshold

    # Consecutive failures before it is taken out.
    unhealthy_threshold = var.unhealthy_threshold

    # Any 2xx counts as healthy.
    matcher = "200-299"
  }

  # Sticky sessions. Off by default: sticky sessions defeat even load
  # distribution and make instance replacement user-visible. Only enable
  # when the application genuinely holds server-side session state.
  dynamic "stickiness" {
    for_each = var.enable_stickiness ? [1] : []

    content {
      type            = "lb_cookie"
      cookie_duration = 86400
      enabled         = true
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-tg" })

  # The target group must exist before the old one is destroyed, because
  # the listener and the ASG both reference it.
  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# LISTENERS
###############################################################################

# ---- HTTP :80 -----------------------------------------------------------
# With a certificate: permanently redirect to HTTPS.
# Without one: forward directly (learning/demo only - see README).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != null ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn == null ? [1] : []

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }

  tags = local.tags
}

# ---- HTTPS :443 ---------------------------------------------------------
# Created only when an ACM certificate ARN is supplied.
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"

  # TLS 1.2 minimum. The older policies still permit TLS 1.0/1.1, which
  # fail PCI DSS and most security reviews.
  ssl_policy      = var.ssl_policy
  certificate_arn = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.tags
}
