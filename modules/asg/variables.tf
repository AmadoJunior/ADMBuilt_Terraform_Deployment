variable "vpc_id" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "max_size" {
  type = number
}
variable "min_size" {
  type = number
}
variable "environment" {
  type = string
}
variable "public_subnets" {
  type = list(string)
}
