resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_db_instance" "main" {
  identifier              = "${var.project_name}-main"
  engine                  = "postgres"
  engine_version          = "16.4"
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 1 # must be > 0 for a read replica to be created
  multi_az                = false

  tags = {
    Name = "${var.project_name}-main-db"
  }
}

resource "aws_db_instance" "replica" {
  count                  = var.create_read_replica ? 1 : 0
  identifier              = "${var.project_name}-replica"
  replicate_source_db     = aws_db_instance.main.identifier
  instance_class          = var.db_instance_class
  publicly_accessible     = false
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true

  tags = {
    Name = "${var.project_name}-replica-db"
  }
}
