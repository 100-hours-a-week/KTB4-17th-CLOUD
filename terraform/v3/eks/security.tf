/** External Kafka and Redis access
 * 외부 SG 자체는 조회만 하고 EKS에서 오는 기존 수신 규칙 네 개를 관리한다.
 */
data "aws_security_group" "kafka_redis" {
  vpc_id = var.vpc_id
  name   = "star23-prod-kafka-redis-sg"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = data.aws_security_group.kafka_redis.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "EKS-v3-BE-Redis"
}

resource "aws_vpc_security_group_ingress_rule" "ws_redis_from_eks" {
  security_group_id            = data.aws_security_group.kafka_redis.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6380
  to_port                      = 6380
  description                  = "EKS-v3-WS-Redis"
}

resource "aws_vpc_security_group_ingress_rule" "kafka_from_eks" {
  security_group_id            = data.aws_security_group.kafka_redis.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9092
  description                  = "EKS-v3-Kafka-broker-1"
}

resource "aws_vpc_security_group_ingress_rule" "kafka_additional_brokers_from_eks" {
  security_group_id            = data.aws_security_group.kafka_redis.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 9094
  to_port                      = 9095
  description                  = "EKS-v3-Kafka-brokers-2-3"
}
