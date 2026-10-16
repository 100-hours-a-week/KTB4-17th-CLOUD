output "distribution_id" {
  description = "CloudFront distribution ID for frontend cache invalidation"
  value       = aws_cloudfront_distribution.fe.id
}
