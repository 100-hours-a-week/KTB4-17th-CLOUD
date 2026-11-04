locals {
  name_prefix       = "star23"
  vpc_cidr          = "10.1.0.0/16"
  nat_gateway_zone  = "2a"
  app_port          = 8080
  mysql_port        = 3306
  postgres_port     = 5432
  version           = "v2"
  health_check_path = "/actuator/health"

  zones = {
    "2a" = {
      az          = "ap-northeast-2a"
      public_cidr = "10.1.1.0/24"
      app_cidr    = "10.1.64.0/24"
      data_cidr   = "10.1.21.0/24"
    }

    "2c" = {
      az          = "ap-northeast-2c"
      public_cidr = "10.1.2.0/24"
      app_cidr    = "10.1.65.0/24"
      data_cidr   = "10.1.22.0/24"
    }
  }
}
