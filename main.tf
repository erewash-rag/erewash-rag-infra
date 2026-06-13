terraform {
  backend "s3" {
    bucket = "erewash-rag-terraform-state"
    key    = "terraform.tfstate"
    region = "eu-west-2"
    encrypt = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "static_site" {
  provider          = aws.us_east_1
  domain_name       = "erewash-rag.co.uk"
  validation_method = "DNS"
  subject_alternative_names = ["www.erewash-rag.co.uk"]
}

# S3 Bucket for static site hosting
resource "aws_s3_bucket" "static_site" {
  bucket = "erewash-rag${var.stack_id != "" ? "-" : ""}${var.stack_id}.co.uk"
  force_destroy = true

  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket = aws_s3_bucket.static_site.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_site_policy" {
  bucket = aws_s3_bucket.static_site.id
  policy = data.aws_iam_policy_document.s3_public_read.json
}

data "aws_iam_policy_document" "s3_public_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_site.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    effect = "Allow"
  }
}

# S3 Bucket for article images
resource "aws_s3_bucket" "article_images" {
  bucket = "erewash-rag-article-images${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "article_images" {
  bucket = aws_s3_bucket.article_images.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls  = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "article_images_policy" {
  bucket = aws_s3_bucket.article_images.id
  policy = data.aws_iam_policy_document.article_images_public_read.json
}

data "aws_iam_policy_document" "article_images_public_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.article_images.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    effect = "Allow"
  }
}

# DynamoDB Table for articles
resource "aws_dynamodb_table" "articles" {
  name           = "articles"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
  tags = {
    Name = "erewash-rag-db"
  }
}

# DynamoDB Table for sources
resource "aws_dynamodb_table" "sources" {
  name           = "sources"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  range_key      = "sourceId"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "sourceId"
    type = "S"
  }

  tags = {
    Name = "erewash-rag-db"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "erewash-rag-lambda-exec${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_full" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess_v2"
}

data "aws_iam_policy_document" "ecr_lambda_access" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
  }
}

resource "aws_ecr_repository_policy" "api" {
  repository = "erewash-rag-api"
  policy     = data.aws_iam_policy_document.ecr_lambda_access.json
}

resource "aws_ecr_repository_policy" "copy_writer" {
  repository = "erewash-rag-copy-writer"
  policy     = data.aws_iam_policy_document.ecr_lambda_access.json
}

resource "aws_ecr_repository_policy" "research_assistant" {
  repository = "erewash-rag-research-assistant"
  policy     = data.aws_iam_policy_document.ecr_lambda_access.json
}

# Lambda Function
resource "aws_lambda_function" "api" {
  function_name = "erewash-rag-api${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "318874356511.dkr.ecr.eu-west-2.amazonaws.com/erewash-rag-api:latest"
  environment {
    variables = {
      api_key = var.erewash_rag_api_key
      logging_level = "INFO"
    }
  }
}

# copy-writer Lambda Function
resource "aws_lambda_function" "copy_writer" {
  function_name = "erewash-rag-copy-writer${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "318874356511.dkr.ecr.eu-west-2.amazonaws.com/erewash-rag-copy-writer:latest"
  timeout       = 900
  environment {
    variables = {
      s3_image_bucket        = "erewash-rag-article-images"
      api_key                = var.erewash_rag_api_key
      aws_access_key_id      = var.copy_writer_aws_access_key_id
      aws_secret_access_key  = var.copy_writer_aws_secret_access_key
      open_ai_api_key        = var.open_ai_api_key
      open_ai_org            = var.open_ai_org
      open_ai_project        = var.open_ai_project
      logging_level          = "INFO"
    }
  }
}

# research-assistant Lambda Function
resource "aws_lambda_function" "research_assistant" {
  function_name = "erewash-rag-research-assistant${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "318874356511.dkr.ecr.eu-west-2.amazonaws.com/erewash-rag-research-assistant:latest"
  timeout       = 300
  environment {
    variables = {
      "erewash_council_news_url": "https://www.erewash.gov.uk/news",
      "erewash_council_max_pages": 2,
      "logging_level": "INFO"
  }
}
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "erewash-rag-api${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  description = "API for erewash-rag"
}

resource "aws_api_gateway_resource" "articles" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "articles"
}

resource "aws_api_gateway_method" "get_articles" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.articles.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_articles" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.articles.id
  http_method = aws_api_gateway_method.get_articles.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw_articles" {
  statement_id  = "AllowAPIGatewayInvokeArticles"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/articles"
}

resource "aws_api_gateway_resource" "article_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.articles.id
  path_part   = "{articleId}"
}

resource "aws_api_gateway_method" "get_article_id" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.article_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_article_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.article_id.id
  http_method = aws_api_gateway_method.get_article_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw_article_id" {
  statement_id  = "AllowAPIGatewayInvokeArticleId"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/articles/*"
}

resource "aws_api_gateway_method" "post_articles" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.articles.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_articles" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.articles.id
  http_method             = aws_api_gateway_method.post_articles.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw_articles_post" {
  statement_id  = "AllowAPIGatewayInvokeArticlesPost"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/articles"
}

resource "aws_api_gateway_method" "delete_article_id" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.article_id.id
  http_method   = "DELETE"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "delete_article_id" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.article_id.id
  http_method             = aws_api_gateway_method.delete_article_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw_article_id_delete" {
  statement_id  = "AllowAPIGatewayInvokeArticleIdDelete"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/DELETE/articles/*"
}

resource "aws_api_gateway_method" "put_article_id" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.article_id.id
  http_method   = "PUT"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "put_article_id" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.article_id.id
  http_method             = aws_api_gateway_method.put_article_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_lambda_permission" "apigw_article_id_put" {
  statement_id  = "AllowAPIGatewayInvokeArticleIdPut"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/PUT/articles/*"
}

resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    aws_api_gateway_integration.get_articles,
    aws_api_gateway_integration.post_articles,
    aws_api_gateway_integration.get_article_id,
    aws_api_gateway_integration.delete_article_id,
    aws_api_gateway_integration.put_article_id
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
}

resource "random_string" "api_key_value" {
   length  = 32
   special = false
}

resource "aws_api_gateway_api_key" "main" {
  name        = "erewash-rag-api-key"
  description = "API key for protected endpoints (POST, PUT, DELETE)"
  enabled     = true
  value       = random_string.api_key_value.result
} 

resource "aws_api_gateway_usage_plan" "main" {
  name = "erewash-rag-usage-plan"
  description = "Usage plan for endpoints requiring API key (POST, PUT, DELETE)"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
} 

resource "aws_cloudfront_distribution" "static_site" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "erewash-rag static site distribution"
  aliases             = ["erewash-rag.co.uk", "www.erewash-rag.co.uk"]

  origin {
    domain_name = aws_s3_bucket.static_site.website_endpoint
    origin_id   = "s3-static-site-origin"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-static-site-origin"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.static_site.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
} 

data "aws_route53_zone" "main" {
  name         = "erewash-rag.co.uk."
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.static_site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "static_site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.static_site.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
} 

# EventBridge rule to trigger research-assistant daily at 12pm UTC
resource "aws_cloudwatch_event_rule" "research_assistant_schedule" {
  name                = "erewash-rag-research-assistant-schedule${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  description         = "Triggers research-assistant lambda daily at 12pm UTC"
  schedule_expression = "cron(0 12 * * ? *)"
}

resource "aws_cloudwatch_event_target" "research_assistant_schedule" {
  rule  = aws_cloudwatch_event_rule.research_assistant_schedule.name
  arn   = aws_lambda_function.research_assistant.arn
  input = "{}"
}

resource "aws_lambda_permission" "eventbridge_research_assistant" {
  statement_id  = "AllowEventBridgeInvokeResearchAssistant"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.research_assistant.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.research_assistant_schedule.arn
}

# EventBridge rule to trigger copy-writer daily at 1pm UTC
resource "aws_cloudwatch_event_rule" "copy_writer_schedule" {
  name                = "erewash-rag-copy-writer-schedule${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  description         = "Triggers copy-writer lambda daily at 1pm UTC"
  schedule_expression = "cron(0 13 * * ? *)"
}

resource "aws_cloudwatch_event_target" "copy_writer_schedule" {
  rule  = aws_cloudwatch_event_rule.copy_writer_schedule.name
  arn   = aws_lambda_function.copy_writer.arn
  input = "{}"
}

resource "aws_lambda_permission" "eventbridge_copy_writer" {
  statement_id  = "AllowEventBridgeInvokeCopyWriter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.copy_writer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.copy_writer_schedule.arn
}