terraform {
  # Partial config -- values supplied via `terraform init -backend-config=...`
  # (see README.md for the exact command using your bootstrap outputs)
  backend "s3" {
    key     = "eks-postgres-rds/terraform.tfstate"
    encrypt = true
  }
}
