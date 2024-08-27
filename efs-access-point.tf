resource "aws_efs_access_point" "default" {
  for_each       = { for mapping in var.efs_mapping : "${mapping.file_system_id}${replace(mapping.file_system_path, "/", "-")}" => mapping }
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

resource "aws_efs_access_point" "ssm-user-data" {
  count       = var.ssm_file_system_id != "" ? 1 : 0
  file_system_id = var.ssm_file_system_id
  root_directory {
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = 755
    }
    path = "/${var.name}/ssm-user-data"
  }
}
