output "be_repository_url" {
  description = "Repository URL for the BE container image"
  value       = aws_ecr_repository.be.repository_url
}

output "ai_repository_url" {
  description = "Repository URL for the AI container image"
  value       = aws_ecr_repository.ai.repository_url
}

output "image_bucket_arn" {
  description = "Image bucket ARN used by the BE task IAM policy"
  value       = aws_s3_bucket.image.arn
}
