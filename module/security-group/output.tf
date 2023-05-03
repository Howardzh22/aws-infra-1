output "app_sg" {
  value = aws_security_group.app_sg
}

output "db_sg" {
  value = aws_security_group.db_sg
}

output "lb_sg" {
  value = aws_security_group.lb_sg
}