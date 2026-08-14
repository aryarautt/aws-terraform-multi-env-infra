output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer. This is the URL users hit. Point a CNAME or Route 53 alias at it for a real domain."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the load balancer, required when creating an alias record."
  value       = aws_lb.this.zone_id
}

output "alb_url" {
  description = "Ready-to-use URL for the application."
  value       = var.certificate_arn != null ? "https://${aws_lb.this.dns_name}" : "http://${aws_lb.this.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group. Passed to the ec2 module so the Auto Scaling Group registers instances with it."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "Name of the target group."
  value       = aws_lb_target_group.this.name
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener."
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener, when a certificate was supplied."
  value       = try(aws_lb_listener.https[0].arn, null)
}
