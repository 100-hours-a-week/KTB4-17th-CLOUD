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

  depends_on = [aws_lb_listener_rule.ws]
}
