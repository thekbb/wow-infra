resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  for_each                = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key == "0" ? "us-east-2a" : "us-east-2b"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  for_each          = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key == "0" ? "us-east-2a" : "us-east-2b"
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public
  domain   = "vpc"
}

resource "aws_nat_gateway" "this" {
  for_each      = aws_subnet.public
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
}

resource "aws_route" "private_nat" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  route_table_id = aws_route_table.private[each.key].id
  subnet_id      = each.value.id
}

resource "aws_security_group" "ecs" {
  name        = "azerothcore-ecs"
  description = "ECS tasks"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Authserver"
    from_port   = var.auth_container_port
    to_port     = var.auth_container_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  ingress {
    description = "Worldserver"
    from_port   = var.world_container_port
    to_port     = var.world_container_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "azerothcore-rds"
  description = "RDS MySQL"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs" {
  name        = "azerothcore-efs"
  description = "EFS"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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

resource "aws_efs_file_system" "data" {
  encrypted = true
}

resource "aws_efs_mount_target" "data" {
  for_each        = aws_subnet.private
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_ecs_cluster" "this" {
  name = "azerothcore-cluster"
}

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/ecs/azerothcore/authserver"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "world" {
  name              = "/ecs/azerothcore/worldserver"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "db_import" {
  name              = "/ecs/azerothcore/db-import"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "azerothcore-ecs-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets" {
  name = "azerothcore-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.secrets.arn
}

locals {
  db_secret_login_database_info     = "${aws_secretsmanager_secret.db.arn}:login_database_info::"
  db_secret_world_database_info     = "${aws_secretsmanager_secret.db.arn}:world_database_info::"
  db_secret_character_database_info = "${aws_secretsmanager_secret.db.arn}:character_database_info::"
}

resource "aws_ecs_task_definition" "auth" {
  family                   = "azerothcore-authserver"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.desired_task_cpu
  memory                   = var.desired_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "authserver"
      image     = var.auth_image
      essential = true
      portMappings = [
        {
          containerPort = var.auth_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "AC_LOGS_DIR", value = "/azerothcore/env/dist/logs" },
        { name = "AC_TEMP_DIR", value = "/azerothcore/env/dist/temp" }
      ]
      secrets = [
        { name = "AC_LOGIN_DATABASE_INFO", valueFrom = local.db_secret_login_database_info }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.auth.name
          awslogs-region        = "us-east-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "world" {
  family                   = "azerothcore-worldserver"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.desired_task_cpu
  memory                   = var.desired_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  volume {
    name = "world-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.data.id
      transit_encryption = "ENABLED"
      root_directory     = "/"
    }
  }

  container_definitions = jsonencode([
    {
      name      = "worldserver"
      image     = var.world_image
      essential = true
      portMappings = [
        {
          containerPort = var.world_container_port
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "world-data"
          containerPath = "/azerothcore/env/dist/data"
          readOnly      = false
        }
      ]
      environment = [
        { name = "AC_DATA_DIR", value = "/azerothcore/env/dist/data" },
        { name = "AC_LOGS_DIR", value = "/azerothcore/env/dist/logs" },
        { name = "AC_CLOSE_IDLE_CONNECTIONS", value = "0" }
      ]
      secrets = [
        { name = "AC_LOGIN_DATABASE_INFO", valueFrom = local.db_secret_login_database_info },
        { name = "AC_WORLD_DATABASE_INFO", valueFrom = local.db_secret_world_database_info },
        { name = "AC_CHARACTER_DATABASE_INFO", valueFrom = local.db_secret_character_database_info }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.world.name
          awslogs-region        = "us-east-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "db_import" {
  family                   = "azerothcore-db-import"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.desired_task_cpu
  memory                   = var.desired_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "db-import"
      image     = var.db_import_image
      essential = true
      environment = [
        { name = "AC_DISABLE_INTERACTIVE", value = "1" },
        { name = "AC_DATA_DIR", value = "/azerothcore/env/dist/data" },
        { name = "AC_LOGS_DIR", value = "/azerothcore/env/dist/logs" },
        { name = "AC_CLOSE_IDLE_CONNECTIONS", value = "0" }
      ]
      secrets = [
        { name = "AC_LOGIN_DATABASE_INFO", valueFrom = local.db_secret_login_database_info },
        { name = "AC_WORLD_DATABASE_INFO", valueFrom = local.db_secret_world_database_info },
        { name = "AC_CHARACTER_DATABASE_INFO", valueFrom = local.db_secret_character_database_info }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.db_import.name
          awslogs-region        = "us-east-2"
          awslogs-stream-prefix = "db-import"
        }
      }
    }
  ])
}

resource "aws_lb" "nlb" {
  name               = "azerothcore-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "auth" {
  name        = "azerothcore-auth"
  port        = var.auth_container_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"
  health_check {
    protocol = "TCP"
    port     = var.auth_container_port
  }
}

resource "aws_lb_target_group" "world" {
  name        = "azerothcore-world"
  port        = var.world_container_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"
  health_check {
    protocol = "TCP"
    port     = var.world_container_port
  }
}

resource "aws_lb_listener" "auth" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 3724
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn
  }
}

resource "aws_lb_listener" "world" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 8085
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.world.arn
  }
}

resource "aws_ecs_service" "auth" {
  name            = "azerothcore-authserver"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.auth.arn
  desired_count   = var.auth_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth.arn
    container_name   = "authserver"
    container_port   = var.auth_container_port
  }

  depends_on = [aws_lb_listener.auth]
}

resource "aws_ecs_service" "world" {
  name            = "azerothcore-worldserver"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.world.arn
  desired_count   = var.world_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.world.arn
    container_name   = "worldserver"
    container_port   = var.world_container_port
  }

  depends_on = [aws_lb_listener.world, aws_efs_mount_target.data]
}
