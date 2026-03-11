resource "aws_db_subnet_group" "this" {
  name       = "azerothcore-db"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "db" {
  name = "azerothcore-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username                = var.db_username
    password                = random_password.db.result
    login_database_info     = "${aws_db_instance.this.address};3306;${var.db_username};${random_password.db.result};${var.db_auth_name}"
    world_database_info     = "${aws_db_instance.this.address};3306;${var.db_username};${random_password.db.result};${var.db_world_name}"
    character_database_info = "${aws_db_instance.this.address};3306;${var.db_username};${random_password.db.result};${var.db_characters_name}"
  })
}

resource "aws_db_instance" "this" {
  identifier             = "azerothcore-mysql"
  engine                 = "mysql"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  username               = var.db_username
  password               = random_password.db.result
  db_name                = var.db_name
  skip_final_snapshot    = true
  publicly_accessible    = false
  multi_az               = false
  deletion_protection    = false
}
