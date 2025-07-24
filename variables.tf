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