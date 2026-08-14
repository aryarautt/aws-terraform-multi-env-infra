output "alb_security_group_id" {
  description = "Security Group for the Application Load Balancer."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security Group for the EC2 application instances."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security Group for the RDS database instance."
  value       = aws_security_group.db.id
}
