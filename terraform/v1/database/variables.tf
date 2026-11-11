variable "database_subnet_id" {
  description = "Subnet for the V1 database EC2 instance."
  type        = string
}

variable "security_group_ids" {
  description = "Existing SSH and database SGs for the V1 database EC2 instance."
  type        = object({ ssh = string, database = string })
}
