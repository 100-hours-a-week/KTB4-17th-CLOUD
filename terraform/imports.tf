import {
  id = "star23/be"
  to = aws_ecr_repository.be
}

import {
  id = "star23/ai"
  to = aws_ecr_repository.ai
}

import {
  id = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an"
  to = aws_s3_bucket.fe
}

import {
  id = "star23-images"
  to = aws_s3_bucket.image
}

import {
  id = "E3LYSMQO2T1UT"
  to = aws_cloudfront_distribution.fe
}