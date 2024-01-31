output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}
output "public_subnets" {
  value       = aws_subnet.public_subnets
  description = "Public Subnets"
}
output "private_subnets" {
  value       = aws_subnet.private_subnets
  description = "Private Subnets"
}
