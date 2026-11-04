module "vpc" { source = "./vpc" }
module "subnet" {
  source = "./subnet"
  vpc_id = module.vpc.id
}
module "routetable" {
  source = "./routetable"
  vpc_id = module.vpc.id
}
