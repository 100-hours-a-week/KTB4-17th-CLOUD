/**
 * Common infrastructure
 *
 * 버킷·이미지 저장소·CDN의 소유권은 common state에만 둔다.
 */
data "terraform_remote_state" "common" {
  backend = "s3"

  config = {
    bucket = "star23-tfstate-975779326240"
    key    = "common/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
