locals {
  name_prefix = "star23"
  app_port = 8080
  mysql_port = 3306
  postgres_port = 5432
  version = "v2"
  health_check_path = "/actuator/health"

  zones = {
    "2a" = {
      az = "ap-northeast-2a"
      public_cidr = "10.0.1.0/24"
      app_cidr = "10.0.11.0/24"
      data_cidr = "10.0.21.0/24"
    }

    "2c" = {
      az = "ap-northeast-2c"
      public_cidr = "10.0.2.0/24"
      app_cidr = "10.0.12.0/24"
      data_cidr = "10.0.22.0/24"
    }
  }
}