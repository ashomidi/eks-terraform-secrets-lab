variable "aws_region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform state (e.g. yourname-tfstate-2026)"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "terraform-locks"
}
