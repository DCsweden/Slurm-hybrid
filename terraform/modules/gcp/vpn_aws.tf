# AWS site-to-site tunnel (peer IP from aws_vpn_connection in root hybrid_vpn.tf).
resource "google_compute_vpn_tunnel" "aws" {
  count = var.aws_vpn_peer_ip != "" ? 1 : 0

  name               = "${var.project_name}-aws-tunnel1"
  region             = var.region
  target_vpn_gateway = google_compute_vpn_gateway.main.id
  peer_ip            = var.aws_vpn_peer_ip
  shared_secret      = var.vpn_shared_secret
  ike_version        = 2

  local_traffic_selector  = ["0.0.0.0/0"]
  remote_traffic_selector = ["0.0.0.0/0"]

  depends_on = [
    google_compute_forwarding_rule.fr_esp,
    google_compute_forwarding_rule.fr_udp500,
    google_compute_forwarding_rule.fr_udp4500,
  ]
}

resource "google_compute_route" "aws_via_vpn" {
  count = var.aws_vpn_peer_ip != "" ? 1 : 0

  name       = "${var.project_name}-to-aws"
  dest_range = var.aws_vpc_cidr
  network    = google_compute_network.main.name
  priority   = 100

  next_hop_vpn_tunnel = google_compute_vpn_tunnel.aws[0].id
}
