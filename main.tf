terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# Configure AWS Provider
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Setup VPC
module "network" {
  source               = "./modules/network"
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_cidr_block       = var.vpc_cidr_block
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Setup Load Balancer & Target Groups
module "lb" {
  source          = "./modules/lb"
  environment     = var.environment
  vpc_id          = module.network.vpc_id
  public_subnets  = module.network.public_subnets.*.id
  certificate_arn = var.certificate_arn
}

# Setup Database 
module "database" {
  source                   = "./modules/database"
  environment              = var.environment
  vpc_id                   = module.network.vpc_id
  private_subnets          = module.network.private_subnets.*.id
  db_username              = var.db_username
  db_password              = var.db_password
  strapi_security_group_id = aws_security_group.strapi.id
}

# Log Group
resource "aws_cloudwatch_log_group" "log_group" {
  name = "/ecs/service"
  tags = {
    Environment = var.environment
  }
}

# --- ECS Task Role ---
data "aws_iam_policy_document" "ecs_task_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name_prefix        = "demo-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role" "ecs_exec_role" {
  name_prefix        = "demo-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "client" {
  family                   = "client"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = 256
  memory                   = 256
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  container_definitions = jsonencode([{
    "image" : format("%s:latest", var.client_ecr_uri),
    "cpu" : 256,
    "memory" : 256,
    "name" : "client",
    "networkMode" : "awsvpc",
    "portMappings" : [
      {
        "containerPort" : 3000,
        "hostPort" : 3000
      }
    ],
    "environment" : concat(var.client_env, [
      {
        "name" : "APP_DOMAIN",
        "value" : "${var.environment}.com"
      },
      {
        "name" : "VITE_API_ENDPOINT",
        "value" : "https://${var.environment}.com"
      }
    ]),
    "logConfiguration" : {
      "logDriver" : "awslogs"
      "options" : {
        "awslogs-group"         = aws_cloudwatch_log_group.log_group.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}
resource "aws_ecs_task_definition" "strapi" {
  family                   = "strapi"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = 512
  memory                   = 512
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  container_definitions = jsonencode([{
    "image" : format("%s:latest", var.strapi_ecr_uri),
    "cpu" : 512,
    "memory" : 512,
    "name" : "strapi",
    "networkMode" : "awsvpc",
    "portMappings" : [
      {
        "containerPort" : 1337,
        "hostPort" : 1337
      }
    ],
    "environment" : concat(var.strapi_env, [
      {
        "name" : "DATABASE_HOST",
        "value" : "${module.database.rds_hostname}"
      },
      {
        "name" : "DATABASE_PORT",
        "value" : "3306"
      },
      {
        "name" : "DATABASE_NAME",
        "value" : "${module.database.rds_db_name}"
      },
      {
        "name" : "DATABASE_USERNAME",
        "value" : "${module.database.rds_username}"
      },
      {
        "name" : "DATABASE_PASSWORD",
        "value" : "${var.db_password}"
      },
    ]),
    "logConfiguration" : {
      "logDriver" : "awslogs"
      "options" : {
        "awslogs-group"         = aws_cloudwatch_log_group.log_group.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  depends_on = [module.database.rds_instance]
}

# ECS Task Security Group
resource "aws_security_group" "client" {
  name   = "${var.environment}-client-security-group"
  vpc_id = module.network.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 3000
    to_port         = 3000
    security_groups = [module.lb.lb_security_group_id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "strapi" {
  name   = "${var.environment}-strapi-security-group"
  vpc_id = module.network.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 1337
    to_port         = 1337
    security_groups = [module.lb.lb_security_group_id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-cluster"
}

# Setup ASG
module "asg" {
  source         = "./modules/asg"
  environment    = var.environment
  vpc_id         = module.network.vpc_id
  cluster_name   = aws_ecs_cluster.main.name
  public_subnets = module.network.public_subnets.*.id
  max_size       = var.asg_max_size
  min_size       = var.asg_min_size
}

# ECS Services
resource "aws_ecs_service" "client" {
  health_check_grace_period_seconds = 0
  propagate_tags                    = "NONE"
  name                              = "${var.environment}-client-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.client.arn
  desired_count                     = var.client_count

  network_configuration {
    security_groups = [aws_security_group.client.id]
    subnets         = module.network.public_subnets.*.id
  }

  load_balancer {
    target_group_arn = module.lb.client_target_group_arn
    container_name   = "client"
    container_port   = 3000
  }

  capacity_provider_strategy {
    capacity_provider = module.asg.capacity_provider_name
    base              = 0
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }
  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  tags       = {}
  depends_on = [module.lb.lb_listener]
}
resource "aws_ecs_service" "strapi" {
  health_check_grace_period_seconds = 0
  propagate_tags                    = "NONE"
  name                              = "${var.environment}-strapi-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.strapi.arn
  desired_count                     = var.strapi_count

  network_configuration {
    security_groups = [aws_security_group.strapi.id]
    subnets         = module.network.public_subnets.*.id
  }

  load_balancer {
    target_group_arn = module.lb.strapi_target_group_arn
    container_name   = "strapi"
    container_port   = 1337
  }

  capacity_provider_strategy {
    capacity_provider = module.asg.capacity_provider_name
    base              = 0
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "cpu"
  }

  tags       = {}
  depends_on = [module.lb.lb_listener, module.database.rds_instance]
}

# # --- ECS Service Auto Scaling ---
# resource "aws_appautoscaling_target" "ecs_strapi_target" {
#   service_namespace  = "ecs"
#   scalable_dimension = "ecs:service:DesiredCount"
#   resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.strapi.name}"
#   min_capacity       = 1
#   max_capacity       = 2
# }

# resource "aws_appautoscaling_policy" "ecs_strapi_target_cpu" {
#   name               = "application-scaling-policy-cpu"
#   policy_type        = "TargetTrackingScaling"
#   service_namespace  = aws_appautoscaling_target.ecs_strapi_target.service_namespace
#   resource_id        = aws_appautoscaling_target.ecs_strapi_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_strapi_target.scalable_dimension

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }

#     target_value       = 90
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 300
#   }
# }

# resource "aws_appautoscaling_policy" "ecs_strapi_target_memory" {
#   name               = "application-scaling-policy-memory"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.ecs_strapi_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_strapi_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_strapi_target.service_namespace

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageMemoryUtilization"
#     }

#     target_value       = 90
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 300
#   }
# }

# resource "aws_appautoscaling_target" "ecs_client_target" {
#   service_namespace  = "ecs"
#   scalable_dimension = "ecs:service:DesiredCount"
#   resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.client.name}"
#   min_capacity       = 1
#   max_capacity       = 2
# }

# resource "aws_appautoscaling_policy" "ecs_client_target_cpu" {
#   name               = "application-scaling-policy-cpu"
#   policy_type        = "TargetTrackingScaling"
#   service_namespace  = aws_appautoscaling_target.ecs_client_target.service_namespace
#   resource_id        = aws_appautoscaling_target.ecs_client_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_client_target.scalable_dimension

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }

#     target_value       = 90
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 300
#   }
# }

# resource "aws_appautoscaling_policy" "ecs_client_target_memory" {
#   name               = "application-scaling-policy-memory"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.ecs_client_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_client_target.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.ecs_client_target.service_namespace

#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageMemoryUtilization"
#     }

#     target_value       = 90
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 300
#   }
# }
