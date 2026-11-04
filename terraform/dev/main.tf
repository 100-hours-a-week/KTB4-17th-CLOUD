module "network" { source = "./network" }
module "ec2" {
  source             = "./ec2"
  subnet_ids         = module.network.subnet_ids
  security_group_ids = local.existing_security_group_ids
}
module "database" {
  source             = "./database"
  subnet_ids         = module.network.subnet_ids
  security_group_ids = local.existing_security_group_ids
}
