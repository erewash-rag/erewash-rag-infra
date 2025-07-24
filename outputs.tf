output "s3_website_url" {
  value = aws_s3_bucket.static_site.website_endpoint
  description = "S3 static site URL"
}

output "lambda_function_arn" {
  value = aws_lambda_function.api.arn
  description = "Lambda function ARN"
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
  description = "API Gateway endpoint URL"
}

output "cloudfront_url" {
  value       = "https://${aws_cloudfront_distribution.static_site.domain_name}"
  description = "CloudFront HTTPS URL for the static site"
} 