variable "environment" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "private_subnets" {
  type = list(string)
}
variable "db_password" {
  description = "RDS root user password"
  type        = string
  sensitive   = true
}
variable "strapi_security_group_id" {
  type = string
}
