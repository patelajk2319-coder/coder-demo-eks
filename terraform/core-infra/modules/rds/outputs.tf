output "address" {
  description = "Hostname of the RDS instance (no port)"
  value       = aws_db_instance.main.address
}

output "database_name" {
  description = "Name of the Coder database"
  value       = aws_db_instance.main.db_name
}

output "admin_username" {
  description = "PostgreSQL administrator username"
  value       = aws_db_instance.main.username
}

output "resource_id" {
  description = "RDS resource ID — needed to build the IAM auth rds-db:connect ARN"
  value       = aws_db_instance.main.resource_id
}
