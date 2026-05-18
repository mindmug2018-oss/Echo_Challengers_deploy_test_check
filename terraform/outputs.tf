# ~/project1-aws/terraform/outputs.tf

output "mgmt_public_ip" {
  description = "Mgmt 서버 공인 IP (SSH 및 Grafana 접속용)"
  value       = aws_instance.mgmt.public_ip
}

output "web1_public_ip" {
  description = "Web1 서버 공인 IP"
  value       = aws_instance.web1.public_ip
}

output "web2_public_ip" {
  description = "Web2 서버 공인 IP"
  value       = aws_instance.web2.public_ip
}

output "db_private_ip" {
  description = "DB 서버 사설 IP (Private subnet)"
  value       = aws_instance.db.private_ip
}

output "alb_dns_name" {
  description = "ALB의 DNS 이름 (서비스 접속용)"
  value       = aws_lb.alb.dns_name
}

output "grafana_url" {
  description = "Grafana 대시보드 URL"
  value       = "http://${aws_instance.mgmt.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus 웹 UI URL"
  value       = "http://${aws_instance.mgmt.public_ip}:9090"
}

output "alertmanager_url" {
  description = "AlertManager 웹 UI URL"
  value       = "http://${aws_instance.mgmt.public_ip}:9093"
}

output "alb_url" {
  description = "ALB로 접속하는 서비스 URL"
  value       = "http://${aws_lb.alb.dns_name}"
}