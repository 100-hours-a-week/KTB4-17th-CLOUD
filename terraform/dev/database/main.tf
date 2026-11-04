terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_instance" "data" {
  ami                         = "ami-0bc151a94289adb52"
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_ids["subnet-046d61dd64b873264"]
  private_ip                  = "10.0.0.9"
  key_name                    = "star23-key"
  vpc_security_group_ids      = [var.security_group_ids.data, var.security_group_ids.ssh]
  iam_instance_profile        = null
  ebs_optimized               = true
  associate_public_ip_address = true
  tags                        = { "Name" : "star23-data-dev" }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    iops                  = 3000
    throughput            = 125
    encrypted             = false
    delete_on_termination = true
    tags                  = {}
  }
}
