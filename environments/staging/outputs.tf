###############################################################################
# Outputs
#
# These are the values you need after an apply - to verify the deployment,
# to feed into other systems, and to capture as portfolio evidence.
#
# Anything containing a hostname or credential is marked `sensitive` so it
# is not printed by default. Read one deliberately with:
#   terraform output -raw db_endpoint
###############################################################################

# ---- Network ----------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Availability Zones this environment spans."
  value       = module.vpc.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB and NAT Gateway)."
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs (EC2)."
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs (RDS)."
  value       = module.vpc.private_db_subnet_ids
}

output "nat_gateway_public_ips" {
  description = "Public IPs of the NAT Gateways. Empty when NAT is disabled. These are the source addresses external services see for outbound traffic."
  value       = module.vpc.nat_gateway_public_ips
}

# ---- Application ------------------------------------------------------------

output "application_url" {
  description = "THE URL TO TEST. Open this in a browser, or curl it, to verify the whole request path works end to end."
  value       = module.alb.alb_url
}

output "alb_dns_name" {
  description = "DNS name of the load balancer."
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the load balancer, for creating an alias record."
  value       = module.alb.alb_zone_id
}

output "target_group_arn" {
  description = "ARN of the target group."
  value       = module.alb.target_group_arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = module.ec2.autoscaling_group_name
}

output "ami_id" {
  description = "AMI the instances were launched from."
  value       = module.ec2.ami_id
}

# ---- Security ---------------------------------------------------------------

output "alb_security_group_id" {
  description = "Security Group of the load balancer."
  value       = module.security_groups.alb_security_group_id
}

output "app_security_group_id" {
  description = "Security Group of the application instances."
  value       = module.security_groups.app_security_group_id
}

output "db_security_group_id" {
  description = "Security Group of the database."
  value       = module.security_groups.db_security_group_id
}

output "ec2_role_arn" {
  description = "IAM role assumed by the EC2 instances."
  value       = module.iam.ec2_role_arn
}

# ---- Database ---------------------------------------------------------------

output "db_endpoint" {
  description = "Database connection endpoint. Resolvable only from inside the VPC."
  value       = try(module.rds[0].db_endpoint, null)
  sensitive   = true
}

output "db_name" {
  description = "Name of the initial database."
  value       = try(module.rds[0].db_name, null)
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the RDS-managed master credentials. The password itself is never in Terraform state."
  value       = try(module.rds[0].db_secret_arn, null)
}

# ---- Storage and monitoring -------------------------------------------------

output "s3_bucket_name" {
  description = "Application S3 bucket."
  value       = module.s3.bucket_id
}

output "log_group_name" {
  description = "CloudWatch Log Group receiving application logs."
  value       = module.cloudwatch.log_group_name
}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = module.cloudwatch.dashboard_name
}

output "alarm_names" {
  description = "Every CloudWatch alarm created."
  value       = module.cloudwatch.alarm_names
}

# ---- Convenience ------------------------------------------------------------

output "verification_commands" {
  description = "Copy-paste commands to verify this deployment."
  value       = <<-EOT

    # 1. Does the application respond through the load balancer?
    curl -I ${module.alb.alb_url}

    # 2. Are the targets healthy?
    aws elbv2 describe-target-health \
      --target-group-arn ${module.alb.target_group_arn} \
      --query 'TargetHealthDescriptions[].{Target:Target.Id,State:TargetHealth.State}' \
      --output table

    # 3. Confirm instances have NO public IP (they are in private subnets)
    aws ec2 describe-instances \
      --filters "Name=tag:Environment,Values=${var.environment}" \
                "Name=instance-state-name,Values=running" \
      --query 'Reservations[].Instances[].{Id:InstanceId,Private:PrivateIpAddress,Public:PublicIpAddress}' \
      --output table

    # 4. Open a shell on an instance with NO SSH and NO open port
    aws ssm start-session --target <instance-id>

    # 5. Read the application logs
    aws logs tail ${module.cloudwatch.log_group_name} --follow

  EOT
}
