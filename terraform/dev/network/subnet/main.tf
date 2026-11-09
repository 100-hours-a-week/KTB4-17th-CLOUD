terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "vpc_id" { type = string }

/**
 * Shared V1 public subnets
 *
 * 키는 기존 EC2 참조와 import 주소를 유지하기 위한 고정 식별자다.
 */
locals {
  public_subnets = {
    "subnet-046d61dd64b873264" = {
      cidr_block = "10.0.0.0/28"
      tags = {
        Name        = "star23-public-subnet-2a-02"
        environment = "dev"
      }
    }
    "subnet-0d6ff6e6460961e3c" = {
      cidr_block = "10.0.1.0/24"
      tags = {
        Name    = "star23-public-subnet-2a-01"
        Service = "star23"
      }
    }
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                                         = var.vpc_id
  cidr_block                                     = each.value.cidr_block
  availability_zone                              = "ap-northeast-2a"
  map_public_ip_on_launch                        = false
  assign_ipv6_address_on_creation                = false
  enable_dns64                                   = false
  private_dns_hostname_type_on_launch            = "ip-name"
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
  tags                                           = each.value.tags

  lifecycle {
    prevent_destroy = true
  }
}

output "ids" { value = { for key, subnet in aws_subnet.public : key => subnet.id } }
