resource "aws_db_subnet_group" "default" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = var.private_subnets

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_security_group" "main" {
  name = "${var.environment}-rds-sg"

  description = "RDS (terraform-managed)"
  vpc_id      = var.vpc_id

  # Only MySQL in
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.strapi_security_group_id]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_instance" "main" {
  identifier = var.environment

  allocated_storage       = 10
  backup_retention_period = 1
  backup_window           = "10:46-11:16"
  maintenance_window      = "Mon:00:00-Mon:03:00"
  db_subnet_group_name    = aws_db_subnet_group.default.name
  engine                  = "mysql"
  engine_version          = "8.0.15"
  instance_class          = "db.t2.micro"
  db_name                 = var.environment
  username                = "admin"
  password                = var.db_password
  port                    = 3306
  publicly_accessible     = false
  storage_encrypted       = false

  vpc_security_group_ids = [aws_security_group.main.id]

  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  skip_final_snapshot         = true
}

