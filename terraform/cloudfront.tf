resource "aws_cloudfront_distribution" "fe" {
  aliases             = ["star23sharp.com"]
  anycast_ip_list_id  = null
  comment             = null
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  staging             = false
  tags = {
    Name = "${local.name_prefix}-cdn"
  }

  wait_for_deployment = true
  web_acl_id          = "arn:aws:wafv2:us-east-1:975779326240:global/webacl/CreatedByCloudFront-46dbb29b/a365bae6-f10f-4faf-bf95-956638af4e59"
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = null
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    function_association {
      event_type   = "viewer-request"
      function_arn = "arn:aws:cloudfront::975779326240:function/star23-spa-routing"
    }
    grpc_config {
      enabled = false
    }
  }
  ordered_cache_behavior {
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    path_pattern               = "/api/*"
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "api.byul23.shop"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  ordered_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    default_ttl                = 0
    field_level_encryption_id  = null
    max_ttl                    = 0
    min_ttl                    = 0
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    path_pattern               = "/ws/*"
    realtime_log_config_arn    = null
    response_headers_policy_id = null
    smooth_streaming           = false
    target_origin_id           = "api.byul23.shop"
    trusted_key_groups         = []
    trusted_signers            = []
    viewer_protocol_policy     = "redirect-to-https"
    grpc_config {
      enabled = false
    }
  }
  origin {
    connection_attempts         = 3
    connection_timeout          = 10
    domain_name                 = "api.byul23.shop"
    origin_access_control_id    = null
    origin_id                   = "api.byul23.shop"
    origin_path                 = null
    response_completion_timeout = 0
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      ip_address_type          = "ipv4"
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  origin {
    connection_attempts         = 3
    connection_timeout          = 10
    domain_name                 = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an.s3-website.ap-northeast-2.amazonaws.com"
    origin_access_control_id    = null
    origin_id                   = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an.s3-website.ap-northeast-2.amazonaws.com-mu3nb6g675c"
    origin_path                 = null
    response_completion_timeout = 0
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      ip_address_type          = "ipv4"
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols     = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  origin {
    connection_attempts         = 3
    connection_timeout          = 10
    domain_name                 = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com"
    origin_access_control_id    = "E14UIE0TN17RGS"
    origin_id                   = "star23-s3-deploy-bucket-975779326240-ap-northeast-2-an.s3.ap-northeast-2.amazonaws.com"
    origin_path                 = null
    response_completion_timeout = 0
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:us-east-1:975779326240:certificate/ed35e165-db15-49d2-ae58-d5460cbcb6e5"
    cloudfront_default_certificate = false
    iam_certificate_id             = null
    minimum_protocol_version       = "TLSv1.3_2025"
    ssl_support_method             = "sni-only"
  }
}
