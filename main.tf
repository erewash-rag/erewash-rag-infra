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
    type = "N"
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

# Lambda Function
resource "aws_lambda_function" "api" {
  function_name = "erewash-rag-api${var.stack_id != "" ? "-" : ""}${var.stack_id}"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "318874356511.dkr.ecr.eu-west-2.amazonaws.com/erewash-rag-api:latest"
  environment {
    variables = {}
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

resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    aws_api_gateway_integration.get_articles,
    aws_api_gateway_integration.get_article_id
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(join(",", [
      aws_api_gateway_integration.get_articles.id,
      aws_api_gateway_integration.get_article_id.id,
      aws_api_gateway_method.get_articles.id,
      aws_api_gateway_method.get_article_id.id,
      aws_api_gateway_resource.articles.id,
      aws_api_gateway_resource.article_id.id
    ]))
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
} 