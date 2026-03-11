output "nlb_dns_name" {
  description = "Public NLB DNS name."
  value       = aws_lb.nlb.dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint address."
  value       = aws_db_instance.this.address
}

output "db_secret_arn" {
  description = "Secrets Manager ARN with DB credentials."
  value       = aws_secretsmanager_secret.db.arn
}

output "db_import_task_definition_arn" {
  description = "ECS task definition ARN for DB import."
  value       = aws_ecs_task_definition.db_import.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "ecs_security_group_id" {
  description = "Security group ID used by ECS tasks."
  value       = aws_security_group.ecs.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = [for s in aws_subnet.private : s.id]
}

output "connection_info" {
  description = "Helpful connection info."
  value = {
    auth_port  = var.auth_container_port
    world_port = var.world_container_port
    realm_host = aws_lb.nlb.dns_name
  }
}
