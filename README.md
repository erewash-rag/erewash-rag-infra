# erewash-rag Infrastructure

This repository contains Terraform code to deploy the erewash-rag stack on AWS, including:
- S3 static site hosting (erewash-rag.co.uk)
- Python Lambda function (erewash-rag-api)
- REST API Gateway (erewash-rag-api)
- All required IAM, VPC, and networking

## Prerequisites
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- AWS CLI configured with appropriate credentials

## Deploy Steps

1. **Prepare the Lambda zip:**
   ```sh
   cd lambda
   zip erewash-rag-api.zip lambda_function.py
   cd ..
   ```
2. **Initialize Terraform:**
   ```sh
   terraform init
   ```
3. **Plan the deployment:**
   ```sh
   terraform plan
   ```
4. **Apply the deployment:**
   ```sh
   terraform apply
   ```

## Outputs
- S3 static site URL
- Lambda function ARN
- API Gateway endpoint URL 