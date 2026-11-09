variable "app_subnet_id" {
  description = "Subnet for the V1 application EC2 instance."
  type        = string
}

variable "messaging_subnet_id" {
  description = "Subnet for the V1 Kafka and Redis EC2 instance."
  type        = string
}

variable "security_group_ids" {
  description = "Existing SSH and application SGs; messaging uses the application SG."
  type        = object({ ssh = string, app = string })
}
