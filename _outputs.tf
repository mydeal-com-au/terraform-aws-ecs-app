output "aws_cloudwatch_log_group_arn" {
  value = aws_cloudwatch_log_group.default.arn
}

output "task_definition_arn" {
  value = var.image != "" ? aws_ecs_task_definition.default[0].arn : ""
}

output "task_definition_arn_without_revision" {
  value = var.image != "" ? aws_ecs_task_definition.default[0].arn_without_revision : ""
}

output "task_definition_revision" {
  value = var.image != "" ? aws_ecs_task_definition.default[0].revision : ""
}
