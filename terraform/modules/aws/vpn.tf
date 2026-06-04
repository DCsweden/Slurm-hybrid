resource "aws_vpn_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-vgw"
  }
}

resource "random_password" "vpn_psk" {
  length  = 32
  special = false
}

# Customer gateway toward GCP is created in root hybrid_vpn.tf once GCP VPN IP is known.
