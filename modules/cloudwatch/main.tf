###############################################################################
# CLOUDWATCH MODULE
#
# Logging, alarms and a dashboard.
#
# The distinction that matters:
#   METRICS are numbers over time (CPU 45%, 200 requests/min). Cheap,
#           aggregated, good for alarms and trends.
#   LOGS    are text records of individual events. Expensive at volume,
#           but the only thing that tells you WHY something broke.
#
# You alarm on metrics, then read logs to diagnose. Both are needed.
#
# ALARM DESIGN: every alarm here sets treat_missing_data explicitly.
# The default ("missing") means an alarm never fires if the metric stops
# being published - which is exactly what happens when the thing you are
# monitoring dies. Getting this wrong produces monitoring that goes silent
# at the precise moment you need it.
###############################################################################

locals {
  tags = merge(var.tags, { Module = "cloudwatch" })

  alarm_actions = var.sns_topic_arn != null ? [var.sns_topic_arn] : (
    var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  )
}

###############################################################################
# LOG GROUP
#
# Created explicitly rather than letting the CloudWatch agent auto-create
# it. Auto-created log groups default to NEVER EXPIRE, which quietly
# accumulates storage charges forever.
###############################################################################

resource "aws_cloudwatch_log_group" "app" {
  # The name is passed in rather than computed here. The environment root
  # defines it once in locals and hands the same string to both this module
  # and the ec2 module. If ec2 instead read this module's OUTPUT, Terraform
  # would see a dependency cycle: ec2 -> cloudwatch (log group) and
  # cloudwatch -> ec2 (ASG name for the alarms).
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.tags, { Name = "${var.name_prefix}-app-logs" })
}

###############################################################################
# SNS TOPIC FOR ALARM NOTIFICATIONS
###############################################################################

resource "aws_sns_topic" "alarms" {
  count = var.create_sns_topic ? 1 : 0

  name = "${var.name_prefix}-alarms"

  tags = merge(local.tags, { Name = "${var.name_prefix}-alarms" })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.create_sns_topic && var.alarm_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email

  # NOTE: AWS sends a confirmation email. The subscription stays
  # "PendingConfirmation" until you click the link - alarms will not
  # reach you before then.
}

###############################################################################
# COMPUTE ALARMS
###############################################################################

resource "aws_cloudwatch_metric_alarm" "asg_high_cpu" {
  count = var.autoscaling_group_name != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-asg-high-cpu"
  alarm_description = "Average CPU across the Auto Scaling Group is sustained above ${var.cpu_alarm_threshold}%."

  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_threshold
  period              = 300

  # Require 2 consecutive breaching periods so a brief spike (a deploy, a
  # cron job) does not page anyone. This is the difference between an alarm
  # people trust and one they mute.
  evaluation_periods = 2

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "asg_status_check" {
  count = var.autoscaling_group_name != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-asg-status-check-failed"
  alarm_description = "An EC2 instance is failing its status checks - the hypervisor or the guest OS is unhealthy."

  namespace   = "AWS/EC2"
  metric_name = "StatusCheckFailed"
  statistic   = "Maximum"

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 2

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

###############################################################################
# LOAD BALANCER ALARMS
###############################################################################

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.alb_arn_suffix != null && var.target_group_arn_suffix != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-alb-unhealthy-hosts"
  alarm_description = "One or more targets are failing ALB health checks."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"
  statistic   = "Maximum"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 60
  evaluation_periods  = 2

  # "breaching" here on purpose: if this metric stops arriving, the target
  # group has no targets at all, which is worse than an unhealthy one.
  treat_missing_data = "breaching"

  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_arn_suffix != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-alb-5xx-errors"
  alarm_description = "The load balancer is returning 5xx responses - the application is erroring or unreachable."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic   = "Sum"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alb_5xx_threshold
  period              = 300
  evaluation_periods  = 1

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  count = var.alb_arn_suffix != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-alb-high-response-time"
  alarm_description = "p95 response time is above ${var.response_time_threshold}s."

  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"

  # p95 rather than Average: an average hides the slow tail that users
  # actually notice.
  extended_statistic = "p95"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.response_time_threshold
  period              = 300
  evaluation_periods  = 2

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

###############################################################################
# DATABASE ALARMS
###############################################################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.db_instance_id != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-rds-high-cpu"
  alarm_description = "Database CPU is sustained above ${var.cpu_alarm_threshold}%."

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_alarm_threshold
  period              = 300
  evaluation_periods  = 2

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  count = var.db_instance_id != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-rds-low-storage"
  alarm_description = "Database free storage has dropped below ${var.rds_free_storage_threshold_gb} GB. A database that fills up stops accepting writes."

  namespace   = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  comparison_operator = "LessThanThreshold"
  # CloudWatch reports this metric in bytes.
  threshold          = var.rds_free_storage_threshold_gb * 1024 * 1024 * 1024
  period             = 300
  evaluation_periods = 1

  treat_missing_data = "breaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count = var.db_instance_id != null ? 1 : 0

  alarm_name        = "${var.name_prefix}-rds-high-connections"
  alarm_description = "Database connection count is unusually high - possible connection leak or missing pooling."

  namespace   = "AWS/RDS"
  metric_name = "DatabaseConnections"
  statistic   = "Average"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.rds_connection_threshold
  period              = 300
  evaluation_periods  = 2

  treat_missing_data = "notBreaching"

  alarm_actions = local.alarm_actions

  tags = local.tags
}

###############################################################################
# DASHBOARD
#
# One page showing the health of every tier. The value is having a single
# place to look during an incident instead of clicking between six consoles.
###############################################################################


# WHY THIS IS BUILT WITH concat() AND for EXPRESSIONS
# ---------------------------------------------------
# The obvious way to make a widget conditional does NOT work in HCL:
#
#     widgets = concat(
#       var.alb_arn_suffix != null ? [widget_a, widget_b] : [],   # ERROR
#     )
#
# HCL rejects it with "Inconsistent conditional result types". A tuple's
# LENGTH is part of its type, so tuple-of-2 and tuple-of-0 are different
# types, and a conditional requires both branches to share one type.
#
# The working pattern is a `for` expression over a list of length 0 or 1:
#
#     [for _ in (cond ? [1] : []) : { ... }]
#
# This is the same idea as `count = cond ? 1 : 0`, applied to a value.

locals {
  alb_widget = var.alb_arn_suffix != null ? [1] : []
  asg_widget = var.autoscaling_group_name != null ? [1] : []
  db_widget  = var.db_instance_id != null ? [1] : []
}

resource "aws_cloudwatch_dashboard" "this" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = concat(
      [for _ in local.alb_widget : {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB - requests and errors"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          ]
        }
      }],

      [for _ in local.alb_widget : {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB - response time"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }],
          ]
        }
      }],

      [for _ in local.asg_widget : {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "EC2 - CPU and capacity"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.autoscaling_group_name, { stat = "Average" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.autoscaling_group_name, { stat = "Average" }],
            [".", "GroupDesiredCapacity", ".", ".", { stat = "Average" }],
          ]
        }
      }],

      [for _ in local.db_widget : {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "RDS - CPU, connections, storage"
          region = var.aws_region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average" }],
            [".", "DatabaseConnections", ".", ".", { stat = "Average" }],
            [".", "FreeStorageSpace", ".", ".", { stat = "Average", yAxis = "right" }],
          ]
        }
      }],
    )
  })
}
