provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_s3_bucket" "website_source" {
  bucket        = "terraform-nick.dev.s522.net"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "block_public_access_website_source" {
  bucket                  = aws_s3_bucket.website_source.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.website_source.id
  policy = data.aws_iam_policy_document.allow_public_read_access.json
}

data "aws_iam_policy_document" "allow_public_read_access" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_source.arn}/*"]
  }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website_source.id
  key          = "hello.gif"
  source       = "files/waving_hello.gif"
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
    name                   = aws_s3_bucket_website_configuration.website_config.website_domain
    zone_id                = aws_s3_bucket.website_source.hosted_zone_id
    evaluate_target_health = true
  }
}

output "domain" {
  value = aws_route53_record.domain.fqdn
}
