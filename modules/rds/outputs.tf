output "db_instance_id" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "Connection endpoint in host:port form. Resolvable only from inside the VPC."
  value       = aws_db_instance.this.endpoint
  sensitive   = true
}

output "db_address" {
  description = "Hostname of the database, without the port."
  value       = aws_db_instance.this.address
  sensitive   = true
}

output "db_port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS-managed master credentials. Passed to the iam module so the application role can read exactly this one secret."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "db_secret_kms_key_id" {
  description = "KMS key ID encrypting the master user secret. The application role needs kms:Decrypt on this key."
  value       = try(aws_db_instance.this.master_user_secret[0].kms_key_id, null)
}

output "db_subnet_group_name" {
  description = "Name of the database subnet group."
  value       = aws_db_subnet_group.this.name
}
