## Networking for the rotation Lambda ##
# AWS's hosted rotation Lambda runs inside your VPC (so it can reach RDS on
# the private DB subnets) but those subnets have no internet route, so it
# also needs a private path to the Secrets Manager API -- hence the
# interface endpoint below instead of relying on internet egress.

resource "aws_security_group" "rotation_lambda" {
  name_prefix = "${var.project_name}-rotation-lambda-"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rotation-lambda-sg"
  }
}

resource "aws_security_group" "secretsmanager_endpoint" {
  name_prefix = "${var.project_name}-sm-endpoint-"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS from the rotation Lambda"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.rotation_lambda.id]
  }

  ingress {
    description     = "HTTPS from EKS nodes (External Secrets Operator)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sm-endpoint-sg"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.db[*].id
  security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

## RDS must accept connections from the rotation Lambda too ##
# (see the rds-sg-fix.md note -- this replaces the single inline ingress
# block in rds.tf with two standalone rule resources)

resource "aws_security_group_rule" "rds_from_eks" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description              = "Postgres from EKS worker nodes"
}

resource "aws_security_group_rule" "rds_from_rotation_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.rotation_lambda.id
  description              = "Postgres from Secrets Manager rotation Lambda"
}

## AWS's prebuilt single-user Postgres rotation Lambda, via the Serverless
## Application Repository -- no custom Lambda code to write or maintain.
data "aws_partition" "current" {}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "postgres_rotator" {
  name           = "${var.project_name}-rotator"
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser"
  capabilities = [
    "CAPABILITY_IAM",
    "CAPABILITY_RESOURCE_POLICY",
  ]

  parameters = {
    functionName        = "${var.project_name}-rotation-fn"
    endpoint            = "https://secretsmanager.${var.aws_region}.${data.aws_partition.current.dns_suffix}"
    vpcSubnetIds        = join(",", aws_subnet.db[*].id)
    vpcSecurityGroupIds = aws_security_group.rotation_lambda.id
  }
}

resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.postgres_rotator.outputs["RotationLambdaARN"]

  rotation_rules {
    # Short interval on purpose -- you want to actually SEE a rotation
    # happen during a practice session, not wait a month for it.
    automatically_after_days = 1
  }

  depends_on = [aws_secretsmanager_secret_version.db_credentials]
}

output "rotation_lambda_arn" {
  value = aws_serverlessapplicationrepository_cloudformation_stack.postgres_rotator.outputs["RotationLambdaARN"]
}
