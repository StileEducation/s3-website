provider "aws" {
  region = "ap-southeast-2"
}

provider "aws" {
  region = "us-east-1"
  alias  = "use1"
}

resource "aws_s3_bucket" "website_source" {
  bucket        = "terraform-nick.dev.s522.net"
  force_destroy = false
}


resource "aws_s3_bucket_ownership_controls" "controls" {
  bucket = aws_s3_bucket.website_source.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "acl" {
  depends_on = [aws_s3_bucket_ownership_controls.controls]

  bucket = aws_s3_bucket.website_source.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "block_public_access_website_source" {
  bucket                  = aws_s3_bucket.website_source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.website_source.id
  policy = data.aws_iam_policy_document.allow_public_read_access.json
}

data "aws_iam_policy_document" "allow_public_read_access" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_source.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.website_source.id
  key    = "hello.gif"
  source = "files/waving_hello.gif"
  # Otherwise the default is an octet stream
  content_type = "image/gif"
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_source.id
  index_document {
    suffix = "hello.gif"
  }
}

data "aws_route53_zone" "dev" {
  name = "dev.s522.net"
}

resource "aws_route53_record" "domain" {
  zone_id = data.aws_route53_zone.dev.zone_id
  name    = "terraform-nick.dev.s522.net"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudfront_origin_access_control" "origin_access_control" {
  name                              = "nick-terraform"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  wait_for_deployment = false
  default_root_object = "hello.gif"

  aliases = ["terraform-nick.dev.s522.net"]

  origin {
    domain_name              = aws_s3_bucket.website_source.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website_source.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.origin_access_control.id
  }

  default_cache_behavior {
    # Managed-CachingOptimized
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.website_source.id}"
    viewer_protocol_policy = "redirect-to-https"
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.cert.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_route53_record" "caa" {
  name    = "terraform-nick.dev.s522.net"
  type    = "CAA"
  zone_id = data.aws_route53_zone.dev.zone_id
  records = [
    "0 issue \"amazon.com\"",
    "0 issue \"amazontrust.com\"",
    "0 issue \"awstrust.com\"",
    "0 issue \"amazonaws.com\"",
  ]
  ttl = 300
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "terraform-nick.dev.s522.net"
  validation_method = "DNS"
  depends_on        = [aws_route53_record.caa]
  lifecycle {
    create_before_destroy = true
  }
  provider = aws.use1
}

resource "aws_route53_record" "validation-record" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type

  zone_id         = data.aws_route53_zone.dev.zone_id
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cert-validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation-record : record.fqdn]
  provider                = aws.use1
}

output "domain" {
  value = aws_route53_record.domain.fqdn
}
