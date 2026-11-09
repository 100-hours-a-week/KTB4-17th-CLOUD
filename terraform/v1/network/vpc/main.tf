terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

/**
 * Shared V1 VPC
 *
 * dev가 네트워크를 소유하되 운영 모니터링과 Lambda도 사용하므로 삭제를 막는다.
 */
resource "aws_vpc" "main" {
  cidr_block                           = "10.0.0.0/16"
  instance_tenancy                     = "default"
  enable_dns_support                   = true
  enable_dns_hostnames                 = false
  enable_network_address_usage_metrics = false

  tags = {
    Name    = "star23-vpc-v1"
    Service = "star23"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "star23-public-igw"
    Service = "star23"
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "id" { value = aws_vpc.main.id }
output "default_route_table_id" { value = aws_vpc.main.default_route_table_id }
output "internet_gateway_id" { value = aws_internet_gateway.main.id }
