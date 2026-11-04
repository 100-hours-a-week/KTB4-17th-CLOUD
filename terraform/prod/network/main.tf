terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "vpc" {
  source      = "./vpc"
  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr
  vpc_version = var.vpc_version
}
module "subnet" {
  source      = "./subnet"
  name_prefix = var.name_prefix
  zones       = var.zones
  vpc_id      = module.vpc.id
}
module "routetable" {
  source                 = "./routetable"
  name_prefix            = var.name_prefix
  zones                  = var.zones
  vpc_id                 = module.vpc.id
  internet_gateway_id    = module.vpc.internet_gateway_id
  nat_gateway_id         = aws_nat_gateway.main[var.nat_gateway_zone].id
  public_subnet_ids      = module.subnet.public_ids
  application_subnet_ids = module.subnet.application_ids
  data_subnet_ids        = module.subnet.data_ids
}
