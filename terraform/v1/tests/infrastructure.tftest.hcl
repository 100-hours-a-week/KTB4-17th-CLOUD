mock_provider "aws" {}

run "managed_shared_v1_network" {
  command = plan

  providers = {
    aws = aws
  }

  # import는 실제 기존 state를 사용하는 별도 계획에서 검증한다.
  # 이 테스트는 편입 파일 없이 네트워크 모듈의 연결 계약을 검증한다.
  module {
    source = "./network"
  }

  override_resource {
    target = module.vpc.aws_vpc.main
    values = {
      id                     = "vpc-0c203bd23ce77e200"
      default_route_table_id = "rtb-0239950e5f3f5d55c"
    }
    override_during = plan
  }
  override_resource {
    target          = module.vpc.aws_internet_gateway.main
    values          = { id = "igw-05c0c3fc9a04af50b" }
    override_during = plan
  }
  override_resource {
    target          = module.routetable.aws_route_table.public
    values          = { id = "rtb-07a5c07f85fda1ee1" }
    override_during = plan
  }
  override_resource {
    target          = module.routetable.aws_default_route_table.main
    values          = { id = "rtb-0239950e5f3f5d55c" }
    override_during = plan
  }
  override_resource {
    target          = module.subnet.aws_subnet.public["subnet-046d61dd64b873264"]
    values          = { id = "subnet-046d61dd64b873264" }
    override_during = plan
  }
  override_resource {
    target          = module.subnet.aws_subnet.public["subnet-0d6ff6e6460961e3c"]
    values          = { id = "subnet-0d6ff6e6460961e3c" }
    override_during = plan
  }

  assert {
    condition     = output.vpc_id == "vpc-0c203bd23ce77e200" && output.internet_gateway_id == "igw-05c0c3fc9a04af50b"
    error_message = "V1 VPC and gateway references must remain connected to the managed network."
  }
  assert {
    condition = tomap(output.subnet_ids) == tomap({
      "subnet-046d61dd64b873264" = "subnet-046d61dd64b873264"
      "subnet-0d6ff6e6460961e3c" = "subnet-0d6ff6e6460961e3c"
    })
    error_message = "Both existing EC2 subnet lookup keys must remain stable during adoption."
  }
  assert {
    condition     = output.route_table_ids.public == "rtb-07a5c07f85fda1ee1" && output.route_table_ids.main == "rtb-0239950e5f3f5d55c"
    error_message = "Public and default V1 route tables must remain distinct."
  }
}
