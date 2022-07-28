terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_cluster" "this" {
  name = "terraform-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# get or create the default vpc
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

# get subnets on the default vpc
data "aws_subnets" "this" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}


resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow http inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description      = "http from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "terraform-managed"
  }
}

# create task and execution rule
resource "aws_iam_role" "task_role" {
  name = "ecs-exec-task-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role" "execution_role" {
  name = "ecs-exec-task-execution-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
# 
resource "aws_iam_policy" "policy" {
  name        = "taskrole-policy"
  description = "ssm"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "taskrole-attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_role_policy_attachment" "executionrole-attach" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}



resource "aws_ecs_task_definition" "task1" {
  family                = "task"
  execution_role_arn = aws_iam_role.execution_role.arn
  task_role_arn =  aws_iam_role.task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  container_definitions = file("task-definitions/task.json")
}


# allow the services to find each other 

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "terraform.local"
  description = "to allo inter connection"
  vpc         = aws_default_vpc.default.id
}

resource "aws_service_discovery_service" "front" {
  name = "front"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}


# service 1 

resource "aws_ecs_service" "service" {
  name            = "backend"
  launch_type = "FARGATE"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task1.arn
  network_configuration {
      subnets = data.aws_subnets.this.ids
      security_groups = [aws_security_group.allow_http.id]
      assign_public_ip = true
  }
    service_registries {
      registry_arn = aws_service_discovery_service.backend.arn
  }
  desired_count   = 1
  enable_execute_command = true
  

}
# service 2 
resource "aws_ecs_service" "service2" {
  name            = "front"
  launch_type = "FARGATE"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task1.arn
  network_configuration {
      subnets = data.aws_subnets.this.ids
      security_groups = [aws_security_group.allow_http.id]
      assign_public_ip = true
  }
  service_registries {
      registry_arn = aws_service_discovery_service.front.arn
  }
  desired_count   = 1
  enable_execute_command = true
}