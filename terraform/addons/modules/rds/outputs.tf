output "address" {
  description = "Hostname of the RDS instance (no port)"
  value       = aws_db_instance.main.address
}

output "database_name" {
  description = "Name of the Coder database"
  value       = aws_db_instance.main.db_name
}
