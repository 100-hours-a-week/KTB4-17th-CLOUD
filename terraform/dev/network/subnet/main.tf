terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "vpc_id" { type = string }
data "aws_subnet" "existing" {
  for_each = toset(["subnet-046d61dd64b873264", "subnet-0d6ff6e6460961e3c"])
  id       = each.value
  vpc_id   = var.vpc_id
}
output "ids" { value = { for id, subnet in data.aws_subnet.existing : id => subnet.id } }
