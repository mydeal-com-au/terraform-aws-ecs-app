resource "aws_ecs_task_definition" "default" {
  count = var.image != "" ? 1 : 0

  family = "${var.cluster_name}-${var.name}"

  execution_role_arn = var.task_role_arn
  task_role_arn      = var.task_role_arn

  requires_compatibilities = [var.launch_type]

  network_mode = var.launch_type == "FARGATE" ? "awsvpc" : var.network_mode
  cpu          = var.launch_type == "FARGATE" ? var.cpu : null
  memory       = var.launch_type == "FARGATE" ? var.memory : null

  container_definitions = jsonencode(concat([
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
        sourceVolume  = "efs-${mapping.file_system_id}${replace(mapping.file_system_path, "/", "-")}"
        containerPath = mapping.container_path
      }]
      secrets     = [for k, v in var.ssm_variables : { name : k, valueFrom : v }]
      environment = [for k, v in var.static_variables : { name : k, value : v }]
      ulimits     = var.ulimits
    }
  ], var.include_ssm_agent ? [
    {
      name        = "amazon-ssm-agent"
      image       = "public.ecr.aws/amazon-ssm-agent/amazon-ssm-agent:latest"
      cpu         = 0
      essential   = false
      command     = [
          "/bin/bash",
          "-c",
          "set -e; yum upgrade -y; yum install jq procps awscli -y; term_handler() { echo \"Deleting SSM activation $ACTIVATION_ID\"; if ! aws ssm delete-activation --activation-id $ACTIVATION_ID --region $ECS_TASK_REGION; then echo \"SSM activation $ACTIVATION_ID failed to be deleted\" 1>&2; fi; MANAGED_INSTANCE_ID=$(jq -e -r .ManagedInstanceID /var/lib/amazon/ssm/registration); echo \"Deregistering SSM Managed Instance $MANAGED_INSTANCE_ID\"; if ! aws ssm deregister-managed-instance --instance-id $MANAGED_INSTANCE_ID --region $ECS_TASK_REGION; then echo \"SSM Managed Instance $MANAGED_INSTANCE_ID failed to be deregistered\" 1>&2; fi; kill -SIGTERM $SSM_AGENT_PID; }; trap term_handler SIGTERM SIGINT; if [[ -z $MANAGED_INSTANCE_ROLE_NAME ]]; then echo \"Environment variable MANAGED_INSTANCE_ROLE_NAME not set, exiting\" 1>&2; exit 1; fi; if ps ax | grep amazon-ssm-agent | grep -v grep > /dev/null; then pkill amazon-ssm-agent; fi; if [[ -n $ECS_CONTAINER_METADATA_URI_V4 ]] ; then echo \"Found ECS Container Metadata, running activation with metadata\"; TASK_METADATA=$(curl \"$${ECS_CONTAINER_METADATA_URI_V4}/task\"); ECS_TASK_AVAILABILITY_ZONE=$(echo $TASK_METADATA | jq -e -r '.AvailabilityZone'); ECS_TASK_ARN=$(echo $TASK_METADATA | jq -e -r '.TaskARN'); ECS_TASK_REGION=$(echo $ECS_TASK_AVAILABILITY_ZONE | sed 's/.$//'); ECS_TASK_AVAILABILITY_ZONE_REGEX='^(af|ap|ca|cn|eu|me|sa|us|us-gov)-(central|north|(north(east|west))|south|south(east|west)|east|west)-[0-9]{1}[a-z]{1}$'; if ! [[ $ECS_TASK_AVAILABILITY_ZONE =~ $ECS_TASK_AVAILABILITY_ZONE_REGEX ]]; then echo \"Error extracting Availability Zone from ECS Container Metadata, exiting\" 1>&2; exit 1; fi; ECS_TASK_ARN_REGEX='^arn:(aws|aws-cn|aws-us-gov):ecs:[a-z0-9-]+:[0-9]{12}:task/[a-zA-Z0-9_-]+/[a-zA-Z0-9]+$'; if ! [[ $ECS_TASK_ARN =~ $ECS_TASK_ARN_REGEX ]]; then echo \"Error extracting Task ARN from ECS Container Metadata, exiting\" 1>&2; exit 1; fi; CREATE_ACTIVATION_OUTPUT=$(aws ssm create-activation --iam-role $MANAGED_INSTANCE_ROLE_NAME --tags Key=ECS_TASK_AVAILABILITY_ZONE,Value=$ECS_TASK_AVAILABILITY_ZONE Key=ECS_TASK_ARN,Value=$ECS_TASK_ARN Key=FAULT_INJECTION_SIDECAR,Value=true --region $ECS_TASK_REGION); ACTIVATION_CODE=$(echo $CREATE_ACTIVATION_OUTPUT | jq -e -r .ActivationCode); ACTIVATION_ID=$(echo $CREATE_ACTIVATION_OUTPUT | jq -e -r .ActivationId); if ! amazon-ssm-agent -register -code $ACTIVATION_CODE -id $ACTIVATION_ID -region $ECS_TASK_REGION; then echo \"Failed to register with AWS Systems Manager (SSM), exiting\" 1>&2; exit 1; fi; amazon-ssm-agent & SSM_AGENT_PID=$!; wait $SSM_AGENT_PID; else echo \"ECS Container Metadata not found, exiting\" 1>&2; exit 1; fi"
        ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.default.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ssm"
        }
      }
      mountPoints = [{
        sourceVolume  = "efs-${var.ssm_file_system_id}-ssm-user-data"
        containerPath = "/.ssm/containers/current/user-data"
      }]
      environment = [
        {
            name  = "MANAGED_INSTANCE_ROLE_NAME",
            value =  var.task_role_arn
        }
       ]
    }
  ] : []))

  dynamic "volume" {
    for_each = { for mapping in var.efs_mapping : "${mapping.file_system_id}${replace(mapping.file_system_path, "/", "-")}" => mapping }

    content {
      name = "efs-${volume.key}"

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.default[volume.key].id
        }
      }
    }
  }

  dynamic "volume" {
    for_each = var.ssm_file_system_id != "" ? [1] : []

    content {
      name = "efs-${var.ssm_file_system_id}-ssm-user-data"

      efs_volume_configuration {
        file_system_id     = var.ssm_file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.ssm-user-data[0].id
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
