output "dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_alb.main.dns_name
}

output "be_target_group_arn" {
  description = "Backend target group, ready to attach to an ECS service."
  value       = aws_lb_target_group.api.arn

  depends_on = [aws_lb_listener.https, aws_lb_listener.http]
}

output "ws_target_group_arn" {
  description = "WebSocket target group, ready to attach to an ECS service."
  value       = aws_lb_target_group.ws.arn

  depends_on = [aws_lb_listener_rule.chat_routes]
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "egress_rule_ids" {
  value = [aws_vpc_security_group_egress_rule.alb_to_app.id, aws_vpc_security_group_egress_rule.alb_to_ws.id]
}
