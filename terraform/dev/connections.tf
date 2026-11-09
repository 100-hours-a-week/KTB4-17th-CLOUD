/**
 * Existing security groups
 *
 * 공유 SG와 prod 소유 VPC 간 접근 규칙은 외부 참조로 유지한다.
 * 규칙 전체를 편입하거나 prod 소유 ingress를 중복 생성하지 않는다.
 */
locals {
  existing_security_group_ids = {
    ssh  = "sg-0208d71a531ef25b9"
    app  = "sg-099a8e5296eb61681"
    data = "sg-0477fb590a93b0686"
  }
}
