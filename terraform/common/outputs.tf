output "image_bucket_arn" {
  description = "Shared image bucket ARN for application IAM policies."
  value       = module.storage.image_bucket_arn
}

output "image_bucket_name" {
  value = module.storage.image_bucket_name
}

output "frontend_bucket_name" {
  value = module.storage.frontend_bucket_name
}

output "be_repository_url" {
  value = module.storage.be_repository_url
}

output "ai_repository_url" {
  value = module.storage.ai_repository_url
}

output "cloudfront_distribution_id" {
  value = module.cdn.distribution_id
}
