# The approved production repair created this rule through the EC2 API.
# Import it on the next normal Terraform run to avoid creating a duplicate.
import {
  to = module.network.aws_vpc_security_group_ingress_rule.ai_from_ws
  id = "sgr-0030fb498843e37b8"
}
