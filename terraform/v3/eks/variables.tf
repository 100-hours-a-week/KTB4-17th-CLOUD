variable "vpc_id" {
  description = "V2 VPC shared by the EKS cluster"
  type        = string
}

variable "nat_gateway_id" {
  description = "V2 NAT Gateway used by the EKS private subnets"
  type        = string
}
