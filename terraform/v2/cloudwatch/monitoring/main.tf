terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

/**
 * Monitoring EC2
 *
 * 복구 AMI의 기존 데이터와 프로그램을 이어받으며, 공개 IPv4는 실행 시 자동 할당한다.
 */
resource "aws_instance" "monitoring" {
  ami                         = var.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = var.subnet_id
  key_name                    = "star23-key"
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  iam_instance_profile        = "star23-monitoring-metrics"
  associate_public_ip_address = true
  ebs_optimized               = true

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
    delete_on_termination = true
  }

  tags = {
    Name        = "star23-mo-v2"
    environment = "prod"
    managed_by  = "terraform"
  }

  /** Public IPv4 lifecycle
   * 중지 중 공인 IP 반납이 인스턴스 교체를 유발하지 않도록 한다.
   */
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [associate_public_ip_address]
  }
}
