output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template."
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the Launch Template."
  value       = aws_launch_template.this.latest_version
}

output "ami_id" {
  description = "AMI ID the instances were launched from."
  value       = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux.id
}
