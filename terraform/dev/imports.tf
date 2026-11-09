/**
 * V1 network adoption
 *
 * 기존 AWS 자원을 생성·교체하지 않고 dev state에 편입하는 일회성 선언이다.
 * 검토한 import plan 적용 완료 후 이 파일만 제거하고 resource 선언은 유지한다.
 */
import {
  to = module.network.module.vpc.aws_vpc.main
  id = "vpc-0c203bd23ce77e200"
}

import {
  to = module.network.module.vpc.aws_internet_gateway.main
  id = "igw-05c0c3fc9a04af50b"
}

import {
  for_each = toset(["subnet-046d61dd64b873264", "subnet-0d6ff6e6460961e3c"])
  to       = module.network.module.subnet.aws_subnet.public[each.key]
  id       = each.value
}

import {
  to = module.network.module.routetable.aws_route_table.public
  id = "rtb-07a5c07f85fda1ee1"
}

import {
  to = module.network.module.routetable.aws_default_route_table.main
  id = "vpc-0c203bd23ce77e200"
}

import {
  to = module.network.module.routetable.aws_route.public_internet
  id = "rtb-07a5c07f85fda1ee1_0.0.0.0/0"
}

import {
  for_each = toset(["subnet-046d61dd64b873264", "subnet-0d6ff6e6460961e3c"])
  to       = module.network.module.routetable.aws_route_table_association.public[each.key]
  id       = "${each.value}/rtb-07a5c07f85fda1ee1"
}
