# Site-to-site VPN: AWS VPC <-> GCP VPC (classic GCP VPN + AWS VGW)
# See README for troubleshooting if tunnel stays DOWN after first apply.

resource "aws_customer_gateway" "gcp" {
  bgp_asn    = 65000
  ip_address = module.gcp.vpn_gateway_external_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.project_name}-cgw-gcp"
  }
}

resource "aws_vpn_gateway_attachment" "main" {
  vpc_id         = module.aws.vpc_id
  vpn_gateway_id = module.aws.vpn_gateway_id
}

resource "aws_vpn_connection" "gcp" {
  vpn_gateway_id          = module.aws.vpn_gateway_id
  customer_gateway_id     = aws_customer_gateway.gcp.id
  type                    = "ipsec.1"
  static_routes_only      = true
  tunnel1_preshared_key   = module.aws.vpn_preshared_key
  tunnel2_preshared_key   = module.aws.vpn_preshared_key

  tags = {
    Name = "${var.project_name}-vpn-gcp"
  }
}

resource "aws_vpn_connection_route" "gcp_cidr" {
  destination_cidr_block = var.gcp_vpc_cidr
  vpn_connection_id      = aws_vpn_connection.gcp.id
}

# GCP VPN tunnel + return route live in module.gcp (depends_on forwarding rules there).

resource "aws_route" "to_gcp_compute" {
  route_table_id         = module.aws.route_table_compute_id
  destination_cidr_block = var.gcp_vpc_cidr
  gateway_id             = module.aws.vpn_gateway_id
}

resource "aws_route" "to_gcp_public" {
  route_table_id         = module.aws.route_table_public_id
  destination_cidr_block = var.gcp_vpc_cidr
  gateway_id             = module.aws.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "gcp_compute" {
  vpn_gateway_id = module.aws.vpn_gateway_id
  route_table_id = module.aws.route_table_compute_id
}

resource "aws_vpn_gateway_route_propagation" "gcp_public" {
  vpn_gateway_id = module.aws.vpn_gateway_id
  route_table_id = module.aws.route_table_public_id
}
