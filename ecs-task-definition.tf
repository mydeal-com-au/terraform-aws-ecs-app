resource "aws_ecs_task_definition" "default" {
  count = var.image != "" ? 1 : 0

  family = "${var.cluster_name}-${var.name}"

  execution_role_arn = var.task_role_arn != null ? var.task_role_arn : aws_iam_role.ecs_task[0].arn
  task_role_arn      = var.task_role_arn != null ? var.task_role_arn : aws_iam_role.ecs_task[0].arn

  requires_compatibilities = [var.launch_type]

  network_mode = var.launch_type == "FARGATE" ? "awsvpc" : var.network_mode
  cpu          = var.launch_type == "FARGATE" ? var.cpu : null
  memory       = var.launch_type == "FARGATE" ? var.memory : null

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      cpu       = var.cpu
      memory    = var.memory
      essential = true
      command   = var.command
      portMappings = [
        {
          containerPort = var.container_port
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.default.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "app"
        }
      }
      mountPoints = length(var.efs_mapping) == 0 ? null : [ for mapping in var.efs_mapping : {
        sourceVolume  = "efs-${mapping.file_system_id}"
        containerPath = mapping.container_path
      }]
      secrets     = [for k, v in var.ssm_variables : { name : k, valueFrom : v }]
      environment = [for k, v in var.static_variables : { name : k, value : v }]
      ulimits     = var.ulimits
    }
  ])

  dynamic "volume" {
    for_each = { for mapping in var.efs_mapping : mapping.file_system_id => mapping }

    content {
      name = "efs-${volume.key}"

      efs_volume_configuration {
        file_system_id     = volume.key
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.default[volume.key].id
        }
      }
    }
  }

  dynamic "runtime_platform" {
    for_each = var.launch_type == "FARGATE" ? [1] : []
    content {
      operating_system_family = var.operating_system_family
      cpu_architecture        = var.cpu_architecture
    }
  }

  lifecycle {
    ignore_changes = [
      container_definitions
    ]
  }
}
