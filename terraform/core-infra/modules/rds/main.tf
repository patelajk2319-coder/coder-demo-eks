resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = var.database_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-sg"
  description = "Allow PostgreSQL access from the EKS cluster only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_instance" "main" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "coder"
  username = var.admin_username
  password = var.admin_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  multi_az                = false
  deletion_protection     = false

  # Demo environment — no final snapshot required, so `task nuke` doesn't hang
  # waiting for a snapshot identifier.
  skip_final_snapshot = true

  tags = var.tags
}
