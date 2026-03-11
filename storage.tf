resource "aws_efs_file_system" "data" {
  encrypted = true
}

resource "aws_efs_mount_target" "data" {
  for_each        = aws_subnet.private
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs.id]
}
