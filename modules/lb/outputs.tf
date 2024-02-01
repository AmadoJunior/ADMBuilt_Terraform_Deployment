output "lb_security_group_id" {
  value       = aws_security_group.lb.id
  description = "The ID of the LB Security Group"
}
output "lb_dns_name" {
  value       = aws_lb.default.dns_name
  description = "The LB DNS Name"
}
output "client_target_group_arn" {
  value       = aws_lb_target_group.client.arn
  description = "The arn of the Client Target Group"
}
output "strapi_target_group_arn" {
  value       = aws_lb_target_group.strapi.arn
  description = "The arn of the Strapi Target Group"
}
output "lb_listener" {
  value       = aws_lb_listener.https
  description = "The LB Listener"
}
