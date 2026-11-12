/** Existing database clients
 * Bastion·마이그레이션 SG는 조회만 하고, DB 수신 규칙은 database에서 관리한다.
 */
data "aws_security_group" "bastion" {
  name   = "ssm-client-sg"
  vpc_id = data.terraform_remote_state.v2.outputs.network.vpc_id
}

data "aws_security_group" "migration" {
  name   = "star23-prod-migration-rabbitmq"
  vpc_id = data.terraform_remote_state.v2.outputs.network.vpc_id
}
