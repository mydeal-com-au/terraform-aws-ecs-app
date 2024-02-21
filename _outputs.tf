output "aws_cloudwatch_log_group_arn" {
  value = aws_cloudwatch_log_group.default.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.default.arn
}

output "task_definition_arn_without_revision" {
  value = aws_ecs_task_definition.default.arn_without_revision
}

output "task_definition_revision" {
  value = aws_ecs_task_definition.default.revision
}
