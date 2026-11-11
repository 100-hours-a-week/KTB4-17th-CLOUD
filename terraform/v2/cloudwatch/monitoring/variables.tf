variable "ami_id" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "ssh_cidrs" { type = set(string) }
variable "grafana_admin_cidrs" { type = set(string) }
variable "lambda_forwarder_security_group_id" { type = string }
