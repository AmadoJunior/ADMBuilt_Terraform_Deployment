variable "vpc_id" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "public_subnets" {
  type = list(string)
}
