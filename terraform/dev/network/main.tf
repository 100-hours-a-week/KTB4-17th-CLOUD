/**
 * Shared V1 VPC and internet gateway
 */
module "vpc" { source = "./vpc" }

/**
 * Shared V1 subnets
 */
module "subnet" {
  source = "./subnet"
  vpc_id = module.vpc.id
}

/**
 * Shared V1 routing tables
 */
module "routetable" {
  source                 = "./routetable"
  vpc_id                 = module.vpc.id
  default_route_table_id = module.vpc.default_route_table_id
  internet_gateway_id    = module.vpc.internet_gateway_id
  subnet_ids             = module.subnet.ids
}
