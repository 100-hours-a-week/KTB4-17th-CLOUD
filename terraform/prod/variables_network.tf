variable "v1_database_network" {
  description = "Existing v1 database VPC, subnet route tables, and database security groups to connect to ECS."
  type = object({
    vpc_id                     = string
    route_table_ids            = set(string)
    mysql_security_group_id    = string
    postgres_security_group_id = string
  })
  default = null
}
