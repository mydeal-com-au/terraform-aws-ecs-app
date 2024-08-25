resource "aws_efs_access_point" "default" {
  for_each       = var.efs_mapping
  file_system_id = each.value.file_system_id
  root_directory {
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = 755
    }
    path = "/${var.name}${each.value.file_system_path}"
  }
}
