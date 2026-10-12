resource "aws_s3_bucket" "image" {
  bucket              = "star23-images"
  bucket_namespace    = "global"
  force_destroy       = false
  object_lock_enabled = false
  region              = "ap-northeast-2"
  tags                = {}
  tags_all            = {}
}

resource "aws_s3_bucket" "fe" {
  bucket              = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an"
  bucket_namespace    = "account-regional"
  force_destroy       = false
  object_lock_enabled = false
  region              = "ap-northeast-2"
  tags                = {}
  tags_all            = {}
}