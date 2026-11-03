resource "aws_iam_role_policy" "ws_s3" {
  count = var.ws_enabled && var.ws_use_backend_config ? 1 : 0

  name = "${var.name_prefix}-ws-s3"
  role = module.runtime.task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${var.image_bucket_arn}/*"
    }]
  })
}
