# 컨테이너 이미지 저장소. 이미지 빌드와 push는 CI가 담당한다.

resource "aws_ecr_repository" "ai" {
  force_delete         = null
  image_tag_mutability = "MUTABLE"
  name                 = "star23/ai"
  region               = "ap-northeast-2"
  tags                 = {}
  tags_all             = {}
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "be" {
  force_delete         = null
  image_tag_mutability = "IMMUTABLE"
  name                 = "star23/be"
  region               = "ap-northeast-2"
  tags                 = {}
  tags_all             = {}
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = false
  }
}
