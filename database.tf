resource "aws_db_subnet_group" "this" {
  name       = "azerothcore-db"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "random_password" "db" {
  length  = 20
  special = true
}

resource "random_id" "db_final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db" {
  name = "azerothcore-db-credentials"
}

resource "aws_secretsmanager_secret" "docker_registry" {
  name = var.docker_registry_credentials_secret_name
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
  allocated_storage         = var.db_allocated_storage
  copy_tags_to_snapshot     = true
  db_name                   = var.db_name
  db_subnet_group_name      = aws_db_subnet_group.this.name
  deletion_protection       = true
  engine                    = "mysql"
  engine_version            = var.db_engine_version
  final_snapshot_identifier = "azerothcore-mysql-final-${random_id.db_final_snapshot_suffix.hex}"
  identifier                = "azerothcore-mysql"
  instance_class            = var.db_instance_class
  multi_az                  = false
  password                  = random_password.db.result
  publicly_accessible       = false
  skip_final_snapshot       = false
  username                  = var.db_username
  vpc_security_group_ids    = [aws_security_group.rds.id]
}
