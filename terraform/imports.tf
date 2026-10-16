# Existing AWS resources managed at their module addresses.

import {
  id = "E3LYSMQO2T1UT"
  to = module.cdn.aws_cloudfront_distribution.fe
}

import {
  id = "star23/be"
  to = module.storage.aws_ecr_repository.be
}

import {
  id = "star23/ai"
  to = module.storage.aws_ecr_repository.ai
}

import {
  id = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an"
  to = module.storage.aws_s3_bucket.fe
}

import {
  id = "star23-images"
  to = module.storage.aws_s3_bucket.image
}
