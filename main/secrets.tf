# AWS Secrets Manager secret holding the DB credentials, in the exact JSON
# shape AWS's hosted RDS rotation Lambda expects.
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/db-credentials"
  recovery_window_in_days = 0 # allows immediate delete on terraform destroy -- fine for a lab

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username             = var.db_username
    password             = var.db_password
    engine               = "postgres"
    host                 = aws_db_instance.main.address
    port                 = 5432
    dbname               = var.db_name
    dbInstanceIdentifier = aws_db_instance.main.identifier
  })

  lifecycle {
    # Rotation will change the password out-of-band -- don't let Terraform
    # fight it back to the original value on the next apply.
    ignore_changes = [secret_string]
  }
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}
