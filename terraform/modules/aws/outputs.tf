output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "vpn_gateway_id" {
  value = aws_vpn_gateway.main.id
}

output "vpn_preshared_key" {
  value     = random_password.vpn_psk.result
  sensitive = true
}

output "route_table_compute_id" {
  value = aws_route_table.compute.id
}

output "route_table_public_id" {
  value = aws_route_table.public.id
}

output "login_public_ip" {
  value = aws_instance.login.public_ip
}

output "login_private_ip" {
  value = aws_instance.login.private_ip
}

output "ctrl1_public_ip" {
  value = aws_instance.ctrl1.public_ip
}

output "ctrl2_public_ip" {
  value = aws_instance.ctrl2.public_ip
}

output "aws_compute_instance_id" {
  value = aws_instance.compute.id
}

output "aws_compute_private_ip" {
  value = aws_instance.compute.private_ip
}

output "aws_compute_hostname" {
  value = var.compute_hostname
}

output "subnet_vpn_id" {
  value = aws_subnet.vpn.id
}
