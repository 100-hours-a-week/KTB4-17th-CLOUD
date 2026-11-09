/**
 * Existing security groups
 *
 * 기존 V1 SG는 외부 소유로 참조하며, 규칙 전체를 이 루트에 편입하지 않는다.
 * V2와의 피어링 및 교차 VPC 접근 규칙은 이전 완료 후 제거했다.
 */
locals {
  existing_security_group_ids = {
    ssh  = "sg-0208d71a531ef25b9"
    app  = "sg-099a8e5296eb61681"
    data = "sg-0477fb590a93b0686"
  }
}
