output "rds_hostname" {
  description = "RDS instance hostname"
  value       = aws_db_instance.main.address
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
  sensitive   = true
}

output "rds_username" {
  description = "RDS instance root username"
  value       = aws_db_instance.main.username
  sensitive   = true
}
output "rds_instance" {
  value       = aws_db_instance.main
  description = "The LB Listener"
}
output "rds_db_name" {
  description = "RDS instance db name"
  value       = aws_db_instance.main.db_name
  sensitive   = true
}
