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

resource "aws_cloudwatch_log_group" "client_data" {
  name              = "/ecs/azerothcore/client-data"
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
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = local.ecs_secret_arns
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
  docker_registry_secret_arn        = local.managed_docker_registry_secret_enabled ? aws_secretsmanager_secret.docker_registry[0].arn : var.docker_registry_credentials_secret_arn
  ecs_secret_arns                   = compact([aws_secretsmanager_secret.db.arn, local.docker_registry_secret_arn])
  registry_credentials              = local.docker_registry_secret_arn == "" ? {} : { repositoryCredentials = { credentialsParameter = local.docker_registry_secret_arn } }
}

resource "aws_ecs_task_definition" "auth" {
  family                   = "azerothcore-authserver"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.desired_task_cpu
  memory                   = var.desired_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    merge(
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
      },
      local.registry_credentials
    )
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
    merge(
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
      },
      local.registry_credentials
    )
  ])
}

resource "aws_ecs_task_definition" "db_import" {
  family                   = "azerothcore-db-import"
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
    merge(
      {
        name      = "db-import"
        image     = var.db_import_image
        essential = true
        mountPoints = [
          {
            sourceVolume  = "world-data"
            containerPath = "/azerothcore/env/dist/data"
            readOnly      = false
          }
        ]
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
      },
      local.registry_credentials
    )
  ])
}

resource "aws_ecs_task_definition" "client_data" {
  family                   = "azerothcore-client-data"
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
    merge(
      {
        name      = "client-data"
        image     = var.client_data_image
        essential = true
        mountPoints = [
          {
            sourceVolume  = "world-data"
            containerPath = "/azerothcore/env/dist/data"
            readOnly      = false
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.client_data.name
            awslogs-region        = "us-east-2"
            awslogs-stream-prefix = "client-data"
          }
        }
      },
      local.registry_credentials
    )
  ])
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
