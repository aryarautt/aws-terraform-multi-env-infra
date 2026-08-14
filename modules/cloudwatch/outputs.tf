output "log_group_name" {
  description = "Name of the application log group. Passed to the ec2 module so the CloudWatch agent knows where to ship logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "log_group_arn" {
  description = "ARN of the application log group."
  value       = aws_cloudwatch_log_group.app.arn
}

output "sns_topic_arn" {
  description = "ARN of the alarm notification topic."
  value       = try(aws_sns_topic.alarms[0].arn, var.sns_topic_arn)
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard."
  value       = try(aws_cloudwatch_dashboard.this[0].dashboard_name, null)
}

output "alarm_names" {
  description = "Names of every alarm created, for verification and evidence capture."
  value = compact(concat(
    aws_cloudwatch_metric_alarm.asg_high_cpu[*].alarm_name,
    aws_cloudwatch_metric_alarm.asg_status_check[*].alarm_name,
    aws_cloudwatch_metric_alarm.alb_unhealthy_hosts[*].alarm_name,
    aws_cloudwatch_metric_alarm.alb_5xx[*].alarm_name,
    aws_cloudwatch_metric_alarm.alb_response_time[*].alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu[*].alarm_name,
    aws_cloudwatch_metric_alarm.rds_free_storage[*].alarm_name,
    aws_cloudwatch_metric_alarm.rds_connections[*].alarm_name,
  ))
}
