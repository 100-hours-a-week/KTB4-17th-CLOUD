terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Existing V1 dev hosts. Shared network and rule ownership stays external.
resource "aws_instance" "app" {
  ami                         = "ami-01121f059d87f7a72"
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_ids["subnet-046d61dd64b873264"]
  private_ip                  = "10.0.0.6"
  key_name                    = "star23-key"
  vpc_security_group_ids      = [var.security_group_ids.ssh, var.security_group_ids.app]
  iam_instance_profile        = "star23-ec2-ecr-pull-iam"
  ebs_optimized               = true
  associate_public_ip_address = true
  tags                        = { "Environment" : "dev", "Name" : "star23-app-dev" }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    iops                  = 3000
    throughput            = 125
    encrypted             = false
    delete_on_termination = true
    tags                  = {}
  }
}


resource "aws_instance" "messaging" {
  ami                         = "ami-0482375b68fabfbaf"
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_ids["subnet-0d6ff6e6460961e3c"]
  private_ip                  = "10.0.1.103"
  key_name                    = "star23-key"
  vpc_security_group_ids      = [var.security_group_ids.app]
  iam_instance_profile        = "star23-ec2-ecr-pull-iam"
  ebs_optimized               = true
  associate_public_ip_address = true
  tags                        = { "Environment" : "dev", "Name" : "star23-kafka,redis-dev" }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    iops                  = 3000
    throughput            = 125
    encrypted             = false
    delete_on_termination = true
    tags                  = {}
  }
}
