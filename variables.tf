variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}

variable "stack_id" {
  description = "Optional stack identifier to be included in resource names (e.g. dev, staging, prod). Default is blank."
  type        = string
  default     = ""
}

variable "erewash_rag_api_key" {
  description = "API key for erewash-rag copy-writer"
  type        = string
  sensitive   = true
}

variable "copy_writer_aws_access_key_id" {
  description = "AWS access key ID for copy-writer lambda"
  type        = string
  sensitive   = true
}

variable "copy_writer_aws_secret_access_key" {
  description = "AWS secret access key for copy-writer lambda"
  type        = string
  sensitive   = true
}

variable "open_ai_api_key" {
  description = "OpenAI API key for copy-writer lambda"
  type        = string
  sensitive   = true
}

variable "open_ai_org" {
  description = "OpenAI organisation for copy-writer lambda"
  type        = string
  sensitive   = true
}

variable "open_ai_project" {
  description = "OpenAI project for copy-writer lambda"
  type        = string
  sensitive   = true
}